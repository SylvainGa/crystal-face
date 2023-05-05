using Toybox.WatchUi as Ui;
using Toybox.Graphics as Graphics;
using Toybox.System as Sys;
using Toybox.Application as App;
using Toybox.ActivityMonitor as ActivityMonitor;
using Toybox.Communications as Comms;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Weather;
using Toybox.Position;
using Toybox.SensorHistory as SensorHistory;
using Toybox.Complications as Complications;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Complications;

using Toybox.Math;

const INTEGER_FORMAT = "%d";

import Toybox.Lang;
import Toybox.WatchUi;

var gThemeColour;
var gMonoLightColour;
var gMonoDarkColour;
var gBackgroundColour;
var gMeterBackgroundColour;
var gHoursColour;
var gMinutesColour;

var gNormalFont;
var gIconsFont;

var gStressLevel;
//DEBUG*/ var gStressLevelLogText;

const SCREEN_MULTIPLIER = (Sys.getDeviceSettings().screenWidth < 360) ? 1 : 2;
//const BATTERY_LINE_WIDTH = 2;
const BATTERY_HEAD_HEIGHT = 4 * SCREEN_MULTIPLIER;
const BATTERY_MARGIN = SCREEN_MULTIPLIER;

var mGarminToOWM = [ 1, 2, 3, 10, 13, 4, 11, 13, 50, 50, 10, 9, 11, 1, 9, 10, 13, 13, 13, 13, 4, 13, 3, 2, 9, 10, 10, 9, 11, 50, 4, 9, 11, 4, 13, 4, 4, 4, 4, 50, 2, 11, 11, 13, 13, 9, 13, 13, 13, 13, 13, 13, 2, 1 ];

//const BATTERY_LEVEL_LOW = 20;
//const BATTERY_LEVEL_CRITICAL = 10;

// x, y are co-ordinates of centre point.
// width and height are outer dimensions of battery "body".
function drawBatteryMeter(dc, x, y, width, height) {
	dc.setColor(gThemeColour, Graphics.COLOR_TRANSPARENT);
	dc.setPenWidth(/* BATTERY_LINE_WIDTH */ 2);

	// Body.
	// drawRoundedRectangle's x and y are top-left corner of middle of stroke.
	// Bottom-right corner of middle of stroke will be (x + width - 1, y + height - 1).
	dc.drawRoundedRectangle(
		x - (width / 2) + /* (BATTERY_LINE_WIDTH / 2) */ 1,
		y - (height / 2) + /* (BATTERY_LINE_WIDTH / 2) */ 1,
		width - /* BATTERY_LINE_WIDTH + 1 */ 1,
		height - /* BATTERY_LINE_WIDTH + 1 */ 1,
		/* BATTERY_CORNER_RADIUS */ 2 * SCREEN_MULTIPLIER);

	// Head.
	// fillRectangle() works as expected.
	dc.fillRectangle(
		x + (width / 2) + BATTERY_MARGIN,
		y - (BATTERY_HEAD_HEIGHT / 2),
		/* BATTERY_HEAD_WIDTH */ 2,
		BATTERY_HEAD_HEIGHT);

	// Fill.
	// #8: battery returned as float. Use floor() to match native. Must match getValueForFieldType().
	var batteryLevel = Math.floor(Sys.getSystemStats().battery);		

	// Fill colour based on battery level.
	var fillColour;
	if (batteryLevel <= /* BATTERY_LEVEL_CRITICAL */ 10) {
		fillColour = Graphics.COLOR_RED;
	} else if (batteryLevel <= /* BATTERY_LEVEL_LOW */ 20) {
		fillColour = Graphics.COLOR_YELLOW;
	} else {
		fillColour = gThemeColour;
	}

	dc.setColor(fillColour, Graphics.COLOR_TRANSPARENT);

	var lineWidthPlusMargin = (/* BATTERY_LINE_WIDTH */ 2 + BATTERY_MARGIN);
	var fillWidth = width - (2 * lineWidthPlusMargin);
	dc.fillRectangle(
		x - (width / 2) + lineWidthPlusMargin,
		y - (height / 2) + lineWidthPlusMargin,
		Math.ceil(fillWidth * (batteryLevel / 100)), 
		height - (2 * lineWidthPlusMargin));
}

var gToggleCounter = 0; // Used to switch between charge and inside temp

function writeBatteryLevel(dc, x, y, width, height, type) {
	var batteryLevel;		
	var textColour;
	
	if (type == 0) { // Standard watch battery is being shown
		batteryLevel = Math.floor(Sys.getSystemStats().battery);

		if (batteryLevel <= /* BATTERY_LEVEL_CRITICAL */ 10) {
			textColour = Graphics.COLOR_RED;
		} else if (batteryLevel <= /* BATTERY_LEVEL_LOW */ 20) {
			textColour = Graphics.COLOR_YELLOW;
		} else {
			textColour = gThemeColour;
		}

		dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(x - (width / 2), y - height, gNormalFont, batteryLevel.toNumber().format(INTEGER_FORMAT) + "%", Graphics.TEXT_JUSTIFY_LEFT);
	}
//****************************************************************
//******** REMVOVED THIS SECTION IF TESLA CODE NOT WANTED ********
//****************************************************************
	else { // Tesla stuff
		textColour = Graphics.COLOR_LT_GRAY; // Default in case we get nothing

		var value = "???";
		var showMode;

		gToggleCounter = (gToggleCounter + 1) & 7; // Increase by one, reset to 0 once 8 is reached. Called every second so incremented every second, giving a two second display of each value
		showMode = gToggleCounter / 2;  // 0-1 is battery, 2-3 Sentry, 4-5 preconditionning, 6-7 is inside temp changed to 0 to 3
		//logMessage("gToggleCounter=" + gToggleCounter + " showMode=" + showMode);

		var teslaInfo = Storage.getValue("TeslaInfo");
		if (teslaInfo != null) {
			var httpErrorTesla = teslaInfo.get("httpErrorTesla");
			var vehicleState = teslaInfo.get("VehicleState");
			var vehicleAsleep = (vehicleState != null && vehicleState.equals("asleep") == true);

			// Only specific error are handled, the others are displayed 'as is' in pink
			if (httpErrorTesla != null && (httpErrorTesla == 200 || httpErrorTesla == 401 || httpErrorTesla == 408)) {
				if (httpErrorTesla == 401) { // No access token, only show the battery (in gray, default above)
					showMode = 0;
				}
				else if (vehicleAsleep || httpErrorTesla == 200) { // Vehicle confirmed asleep (even if we got a 408, we'll add a "?" after the battery level to show this) or we got valid data
					textColour = gThemeColour; // Defaults to theme's color
				}

				if (vehicleAsleep) { // If confirnmed asleep, only show battery and preconditionning (0 and 2)
					showMode &= 2;
				}

				switch (showMode) {
					case 0:
						var suffix = "";

						batteryLevel = teslaInfo.get("BatteryLevel");
						if (batteryLevel != null) {
							var chargingState = teslaInfo.get("ChargingState");
							if (httpErrorTesla == 401 || (!vehicleAsleep && httpErrorTesla == 408)) { // Can't get or token (will be shown in gray) or we got a 408 while not asleep (will be shown in the theme's color)
								suffix = "?";
							}
							else if (vehicleAsleep) {
								suffix = "s";
							}
							else if (chargingState != null && chargingState.equals("Charging") == true) {
								suffix = "+";
							}

							value = batteryLevel + "%" + suffix;

							// If we're in theme's color, reset the color based on battery level, similar to the phone's battery
							if (batteryLevel <= /* BATTERY_LEVEL_CRITICAL */ 10 && textColour == gThemeColour) {
								textColour = Graphics.COLOR_RED;
							} else if (batteryLevel <= /* BATTERY_LEVEL_LOW */ 20 && textColour == gThemeColour) {
								textColour = Graphics.COLOR_YELLOW;
							}
						}
						else {
							value = "???%";
						}
						break;

					case 1:
						var sentryEnabled = teslaInfo.get("SentryEnabled");
						if (sentryEnabled != null) {
							value = (sentryEnabled ? "S on" : "S off");
						}
						else {
							value = "S ???";
						}
						break;

					case 2:
						var precondEnabled = teslaInfo.get("PrecondEnabled");
						if (precondEnabled != null) {
							value = (sentryEnabled ? "P on" : "P off");
						}
						else {
							value = "P ???";
						}
						break;

					case 3:
						var insideTemp = teslaInfo.get("InsideTemp");
						if (insideTemp != null) {
							value = (Sys.getDeviceSettings().temperatureUnits == Sys.UNIT_METRIC ? insideTemp.toNumber() + "°C" : ((insideTemp.toNumber() * 9) / 5 + 32).format("%d") + "°F"); 
						}
						else {
							value = (Sys.getDeviceSettings().temperatureUnits == Sys.UNIT_METRIC ? "???°C" : "???°F");
						}
						break;
				}
			}
			else {
				if (httpErrorTesla != null) {
					value = httpErrorTesla.toString();
				}
				textColour = Graphics.COLOR_PINK; // None handled error
			} 
		}

		//logMessage("value=" + value);		
		dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
		dc.drawText(x - (width / 2), y - height, gNormalFont, value, Graphics.TEXT_JUSTIFY_LEFT );
	}
//****************************************************************
//******************** END OF REMVOVED SECTION *******************
//****************************************************************
}

function updateComplications(complicationName, storageName, index, complicationType) {
	if (Toybox has :Complications) {
		// Check if we should subscribe to our Tesla Complication
		var iter = Complications.getComplications();
		if (iter == null) {
			return;
		}
		var complicationId = iter.next();

		while (complicationId != null) {
			//logMessage(complicationId.longLabel.toString());
			if (complicationId.getType() == complicationType || (complicationId.getType() == Complications.COMPLICATION_TYPE_INVALID && complicationId.longLabel != null && complicationId.longLabel.equals(complicationName))) {
				//DEBUG*/ logMessage("Found complication " + complicationName + " with type " + complicationType);
				break;
			}
			complicationId = iter.next();
		}

		if (complicationId != null) {
			if (complicationId.getType() == Complications.COMPLICATION_TYPE_INVALID) {
				complicationId = complicationId.complicationId;
			}
			else {
				complicationId = new Complications.Id(complicationType);
			}
			if (index != null) {
				Storage.setValue(storageName + index, complicationId);
				Complications.subscribeToUpdates(complicationId);
			}
		}
	}
}


class CrystalView extends Ui.WatchFace {
	private var mIsSleeping = false;
	private var mIsBurnInProtection = false; // Is burn-in protection required and active?
	private var mBurnInProtectionChangedSinceLastDraw = false; // Did burn-in protection change since last full update?
	private var mSettingsChangedSinceLastDraw = true; // Have settings changed since last full update?
	private var mTime;
	var mDataFields;
	var mHasGarminWeather;
	// Cache references to drawables immediately after layout, to avoid expensive findDrawableById() calls in onUpdate();
	var mDrawables = {};

	private var mUseComplications;

	// N.B. Not all watches that support SDK 2.3.0 support per-second updates e.g. 735xt.
	private const PER_SECOND_UPDATES_SUPPORTED = Ui.WatchFace has :onPartialUpdate;

	// private enum /* THEMES */ {
	// 	THEME_BLUE_DARK,
	// 	THEME_PINK_DARK,
	// 	THEME_GREEN_DARK,
	// 	THEME_MONO_LIGHT,
	// 	THEME_CORNFLOWER_BLUE_DARK,
	// 	THEME_LEMON_CREAM_DARK,
	// 	THEME_DAYGLO_ORANGE_DARK,
	// 	THEME_RED_DARK,
	// 	THEME_MONO_DARK,
	// 	THEME_BLUE_LIGHT,
	// 	THEME_GREEN_LIGHT,
	// 	THEME_RED_LIGHT,
	// 	THEME_VIVID_YELLOW_DARK,
	// 	THEME_DAYGLO_ORANGE_LIGHT,
	// 	THEME_CORN_YELLOW_DARK
	// }

	// private enum /* COLOUR_OVERRIDES */ {
	// 	FROM_THEME = -1,
	// 	MONO_HIGHLIGHT = -2,
	// 	MONO = -3
	// }

	function initialize() {
		WatchFace.initialize();

		rereadWeatherMethod();
	}

	function burnInProtectionIsOrWasActive() {
		return mIsBurnInProtection | mBurnInProtectionChangedSinceLastDraw;
	}

	// Reread Weather method
	function rereadWeatherMethod() {
		var owmKeyOverride = $.getStringProperty("OWMKeyOverride","");
		//2022-04-10 logMessage("OWMKeyOverride is '" + owmKeyOverride + "'");
		if (owmKeyOverride == null || owmKeyOverride.length() == 0) {
			if (Toybox has :Weather) {
				mHasGarminWeather = true;
				//2022-04-10 logMessage("Does support Weather");
			} else {
				mHasGarminWeather = false;
				//2022-04-10 logMessage("Does not support Weather");
			}
		} else {
				mHasGarminWeather = false;
				//2022-04-10 logMessage("Using OpenWeatherMap");
		}
	}
	
	// Load your resources here
	function onLayout(dc) {
		gIconsFont = Ui.loadResource(Rez.Fonts.IconsFont);

		setLayout(Rez.Layouts.WatchFace(dc));
		cacheDrawables();
	}

	function cacheDrawables() {
		mDrawables[:LeftGoalMeter] = View.findDrawableById("LeftGoalMeter");
		mDrawables[:RightGoalMeter] = View.findDrawableById("RightGoalMeter");
		mDrawables[:DataArea] = View.findDrawableById("DataArea");
		mDrawables[:Indicators] = View.findDrawableById("Indicators");

		// Use mTime instead.
		// Cache reference to ThickThinTime, for use in low power mode. Saves nearly 5ms!
		// Slighly faster than mDrawables lookup.
		//mDrawables[:Time] = View.findDrawableById("Time");
		mTime = View.findDrawableById("Time");

		// Use mDataFields instead.
		//mDrawables[:DataFields] = View.findDrawableById("DataFields");
		mDataFields = View.findDrawableById("DataFields");

		mDrawables[:MoveBar] = View.findDrawableById("MoveBar");

		setHideSeconds($.getIntProperty("HideSeconds", 0)); // Requires mTime, mDrawables[:MoveBar];
	}

	/*
	// Called when this View is brought to the foreground. Restore
	// the state of this View and prepare it to be shown. This includes
	// loading resources into memory.
	function onShow() {
	}
	*/

	// Set flag to respond to settings change on next full draw (onUpdate()), as we may be in 1Hz (lower power) mode, and cannot
	// update the full screen immediately. This is true on real hardware, but not in the simulator, which calls onUpdate()
	// immediately. Ui.requestUpdate() does not appear to work in 1Hz mode on real hardware.
	function onSettingsChanged() {
		mSettingsChangedSinceLastDraw = true;
		//logMessage("onSettingsChanged called");

		updateNormalFont();

		// Themes: explicitly set *Colour properties that have no corresponding (user-facing) setting.
		updateThemeColours();

		// Update hours/minutes colours after theme colours have been set.
		updateHoursMinutesColours();

		if (CrystalApp has :checkPendingWebRequests) { // checkPendingWebRequests() can be excluded to save memory.
			App.getApp().checkPendingWebRequests();
		}
		
		rereadWeatherMethod(); // Check if we changed from Garmin Weather or OWM

		if (mHasGarminWeather == true) { // Using the Garmin Weather stuff
			ReadWeather(false);
		}	

		// Reread our complications if we're allowed
		mUseComplications = $.getBoolProperty("UseComplications", false);
		if (Toybox has :Complications) {
			// First we drop all our subscriptions before building a new list
			Complications.unsubscribeFromAllUpdates();
			// We listen for complications if we're allowed
			Complications.registerComplicationChangeCallback(mUseComplications ? self.method(:onComplicationUpdated) : null);
		}
	}

    function onComplicationUpdated(complicationId) {
		var complication = Complications.getComplication(complicationId);
		var complicationType = complication.getType();
		//DEBUG*/ var complicationLabel = complication.shortLabel;
		var complicationValue = complication.value;

		//if (complicationType == Complications.COMPLICATION_TYPE_STRESS) {
			//DEBUG*/ logMessage("Type: " + complicationType + " Label: " + complicationLabel + " Value:" + complicationValue + " burnIn active? " + mIsBurnInProtection);
		//}

		// If we were told to ignore complications, do so (but technicaly, we shouldn't get here as we shouldn't be listening in the first place!)
		if (!mUseComplications) {
			/*DEBUG*/ logMessage("How did we get here, we're not supposed to be listening!");
			return;
		}

		// I've seen this while in low power mode, so skip it
		if (complicationValue == null) {
			//DEBUG*/ logMessage("We got a Complication value of null for " + complicationType);
			return;
		}

		// Do fields first
		var app = App.getApp();
		var fieldCount = $.getIntProperty("FieldCount", 3);
		var fieldTypes = app.mFieldTypes;

		for (var i = 0; i < fieldCount; i++) {
			if (fieldTypes[i].get("ComplicationType") == complicationType) {
				fieldTypes[i].put("ComplicationValue", complicationValue);
			}
		}

		// Now do goals
		var goalTypes = app.mGoalTypes;

		for (var i = 0; i < 2; i++) {
			if (goalTypes[i].get("ComplicationType") == complicationType) {
				goalTypes[i].put("ComplicationValue", complicationValue);
			}
		}
    }

	// Read the weather from the Garmin API and store it into the same format OpenWeatherMap expects to see
	function ReadWeather(fromComplication) {
		var weather;
		if (fromComplication) {
		}
		else {
			weather = Weather.getCurrentConditions();
		}
		var result;
		if (weather != null) {
			var temperature = weather.temperature;
			var humidity = weather.relativeHumidity;
			var condition = weather.condition;
			var icon = "01";
			var day = "d";
			
			var myLocation = weather.observationLocationPosition;
			var myLocationArray = myLocation.toDegrees();

			// So the OWM code knows our location since it's background code won't run to fetch it
			gLocationLat = myLocationArray[0];
			gLocationLng = myLocationArray[1];
			
			var now = Time.now();
			if (Toybox.Weather has :getSunrise) {
				//logMessage("We have sunrise and sunset routines!");
				var sunrise = Weather.getSunrise(myLocation, now);
				var sunset = Weather.getSunset(myLocation, now);

				var sinceSunrise = sunrise.compare(now);
				var sinceSunset = now.compare(sunset);
				if (sinceSunrise >= 0 || sinceSunset >= 0) {
					day = "n";
				}

				/*var nowtime = Gregorian.info(now, Time.FORMAT_MEDIUM);
				var nowStr = nowtime.day + " " + nowtime.hour + ":" + nowtime.min.format("%02d") + ":" + nowtime.sec.format("%02d");
				var sunrisetime = Gregorian.info(sunrise, Time.FORMAT_MEDIUM);
				var sunsettime = Gregorian.info(sunset, Time.FORMAT_MEDIUM);
				var sunriseStr = sunrisetime.day + " " + sunrisetime.hour + ":" + sunrisetime.min.format("%02d") + ":" + sunrisetime.sec.format("%02d");
				var sunsetStr = sunsettime.day + " " + sunsettime.hour + ":" + sunsettime.min.format("%02d") + ":" + sunsettime.sec.format("%02d");
				logMessage("For=" + nowStr);
				logMessage("Sunrise=" + sunriseStr);
				logMessage("Sunset=" + sunsetStr);
				logMessage("Since sunrize " + sinceSunrise);
				logMessage("Since sunset " + sinceSunset);*/

			} else {
				//logMessage("Sucks, We DON'T have sunrise and sunset routines, do it the old way then");
				
				now = Gregorian.info(now, Time.FORMAT_SHORT);

				// Convert to same format as sunTimes, for easier comparison. Add a minute, so that e.g. if sun rises at
				// 07:38:17, then 07:38 is already consided daytime (seconds not shown to user).
				now = now.hour + ((now.min + 1) / 60.0);
				//logMessage(now);

				// Get today's sunrise/sunset times in current time zone.
				var sunTimes = getSunTimes(myLocationArray[0], myLocationArray[1], null, /* tomorrow */ false);
				//logMessage(sunTimes);
				//logMessage("now=" + now); 
				//logMessage("sunTimes=" + sunTimes); 
				// If sunrise/sunset happens today.
				var sunriseSunsetToday = ((sunTimes[0] != null) && (sunTimes[1] != null));
				if (sunriseSunsetToday) {
					if (now < sunTimes[0] || now > sunTimes[1]) {
						day = "n";
					}
				}
				
			}

			if (condition < 53) {
				icon = (mGarminToOWM[condition]).format("%02d") + day;
				//logMessage("icon=" + icon); 
			}
			result = { "cod" => 200, "temp" => temperature, "humidity" => humidity, "icon" => icon, "dt" => weather.observationTime.value(), "lat" => myLocationArray[0], "lon" => myLocationArray[1]};
			//2022-04-10 logMessage("Weather at " + weather.observationLocationName + " is " + result);
		} else {
			result = null;
			//2022-04-10 logMessage("No weather data, returning null");
		}
		Storage.setValue("OpenWeatherMapCurrent", result);
		Storage.setValue("NewOpenWeatherMapCurrent", true);
	}	

	// Select normal font, based on whether time zone feature is being used.
	// Saves memory when cities are not in use.
	// Update drawables that use normal font.
	function updateNormalFont() {
		var city = $.getStringProperty("LocalTimeInCity","");

		// #78 Setting with value of empty string may cause corresponding property to be null.
		gNormalFont = Ui.loadResource(((city != null) && (city.length() > 0)) ?
			Rez.Fonts.NormalFontCities : Rez.Fonts.NormalFont);
	}

	function updateThemeColours() {

		// #182 Protect against null or unexpected type e.g. String.
		var theme = $.getIntProperty("Theme", 0);
		var lightFlag;
		var themeOverride = $.getStringProperty("ThemeOverride","");

		gThemeColour = null; // Will still be null if our override is invalid
		if (themeOverride.equals("") == false) {
			try {
				gThemeColour = themeOverride.toNumberWithBase(16);
			}
			catch (e) {
			}
			lightFlag = $.getBoolProperty("ThemeLightOverride", false);
		}

		if (gThemeColour == null) {
			// Theme-specific colours.
			gThemeColour = [
				Graphics.COLOR_BLUE,     // THEME_BLUE_DARK
				Graphics.COLOR_PINK,     // THEME_PINK_DARK
				Graphics.COLOR_GREEN,    // THEME_GREEN_DARK
				Graphics.COLOR_DK_GRAY,  // THEME_MONO_LIGHT
				0x55AAFF,                // THEME_CORNFLOWER_BLUE_DARK
				0xFFFFAA,                // THEME_LEMON_CREAM_DARK
				Graphics.COLOR_ORANGE,   // THEME_DAYGLO_ORANGE_DARK
				Graphics.COLOR_RED,      // THEME_RED_DARK
				Graphics.COLOR_WHITE,    // THEME_MONO_DARK
				Graphics.COLOR_DK_BLUE,  // THEME_BLUE_LIGHT
				Graphics.COLOR_DK_GREEN, // THEME_GREEN_LIGHT
				Graphics.COLOR_DK_RED,   // THEME_RED_LIGHT
				0xFFFF00,                // THEME_VIVID_YELLOW_DARK
				Graphics.COLOR_ORANGE,   // THEME_DAYGLO_ORANGE_LIGHT
				Graphics.COLOR_YELLOW    // THEME_CORN_YELLOW_DARK
			][theme];

			// Light/dark-specific colours.
			var lightFlags = [
				false, // THEME_BLUE_DARK
				false, // THEME_PINK_DARK
				false, // THEME_GREEN_DARK
				true,  // THEME_MONO_LIGHT
				false, // THEME_CORNFLOWER_BLUE_DARK
				false, // THEME_LEMON_CREAM_DARK
				false, // THEME_DAYGLO_ORANGE_DARK
				false, // THEME_RED_DARK
				false, // THEME_MONO_DARK
				true,  // THEME_BLUE_LIGHT
				true,  // THEME_GREEN_LIGHT
				true,  // THEME_RED_LIGHT
				false, // THEME_VIVID_YELLOW_DARK
				true,  // THEME_DAYGLO_ORANGE_LIGHT
				false, // THEME_CORN_YELLOW_DARK
			];

			lightFlag = lightFlags[theme];
		}

		// #124: fr45 cannot show grey. SG Fr45 not supported
		//var isFr45 = (Sys.getDeviceSettings().screenWidth == 208);

		if (lightFlag) {
			gMonoLightColour = Graphics.COLOR_BLACK;
			gMonoDarkColour = /*isFr45 ? Graphics.COLOR_BLACK : */ Graphics.COLOR_DK_GRAY;			
			
			gMeterBackgroundColour = /*isFr45 ? Graphics.COLOR_BLACK : */ Graphics.COLOR_LT_GRAY;
			gBackgroundColour = Graphics.COLOR_WHITE;
		} else {
			gMonoLightColour = Graphics.COLOR_WHITE;
			gMonoDarkColour = /*isFr45 ? Graphics.COLOR_WHITE : */ Graphics.COLOR_LT_GRAY;

			gMeterBackgroundColour = /*isFr45 ? Graphics.COLOR_WHITE : */ Graphics.COLOR_DK_GRAY;
			gBackgroundColour = Graphics.COLOR_BLACK;
		}
	}

	function updateHoursMinutesColours() {
		var overrideColours = [
			gThemeColour,     // FROM_THEME
			gMonoLightColour, // MONO_HIGHLIGHT
			gMonoDarkColour   // MONO
		];

		// #182 Protect against null or unexpected type e.g. String.
		// #182 Protect against invalid integer values (still crashing with getIntProperty()).
		var hco = $.getIntProperty("HoursColourOverride", 0);
		gHoursColour = overrideColours[(hco < 0 || hco > 2) ? 0 : hco];

		var mco = $.getIntProperty("MinutesColourOverride", 0);
		gMinutesColour = overrideColours[(mco < 0 || mco > 2) ? 0 : mco];
	}

	function onSettingsChangedSinceLastDraw() {
		if (!mIsBurnInProtection) {

			// Recreate background buffers for each meter, in case theme colour has changed.	
			mDrawables[:LeftGoalMeter].onSettingsChanged(0);
			mDrawables[:RightGoalMeter].onSettingsChanged(1);

			mDrawables[:MoveBar].onSettingsChanged();	

			mDataFields.onSettingsChanged();	

			mDrawables[:Indicators].onSettingsChanged();
		}

		// If watch does not support per-second updates, and watch is sleeping, do not show seconds immediately, as they will not 
		// update. Instead, wait for next onExitSleep(). 
		if (PER_SECOND_UPDATES_SUPPORTED || !mIsSleeping) { 
			setHideSeconds($.getIntProperty("HideSeconds", 0)); 
		} 

		mSettingsChangedSinceLastDraw = false;
	}

	// Update the view
	function onUpdate(dc) {
		//Sys.println("onUpdate()");

		// If burn-in protection has changed, set layout appropriate to new burn-in protection state.
		// If turning on burn-in protection, free memory for regular watch face drawables by clearing references. This means that
		// any use of mDrawables cache must only occur when burn in protection is NOT active.
		// If turning off burn-in protection, recache regular watch face drawables.
		if (mBurnInProtectionChangedSinceLastDraw) {
			setLayout(mIsBurnInProtection ? Rez.Layouts.AlwaysOn(dc) : Rez.Layouts.WatchFace(dc));
			cacheDrawables();
			mBurnInProtectionChangedSinceLastDraw = false;
		}

		// Respond now to any settings change since last full draw, as we can now update the full screen.
		if (mSettingsChangedSinceLastDraw) {
			onSettingsChangedSinceLastDraw();
		}

		// Clear any partial update clipping.
		if (dc has :clearClip) {
			dc.clearClip();
		}

		updateGoalMeters();

		// Call the parent onUpdate function to redraw the layout
		View.onUpdate(dc);
	}

	// Update each goal meter separately, then also pass types and values to data area to draw goal icons.
	function updateGoalMeters() {
		if (mIsBurnInProtection) {
			return;
		}

		var leftType = $.getIntProperty("LeftGoalType", 0);
		var leftValues = getValuesForGoalType(0, leftType);
		mDrawables[:LeftGoalMeter].setValues(leftValues[:current], leftValues[:max], /* isOff */ leftType == GOAL_TYPE_OFF);

		var rightType = $.getIntProperty("RightGoalType", 1);
		var rightValues = getValuesForGoalType(1, rightType);
		mDrawables[:RightGoalMeter].setValues(rightValues[:current], rightValues[:max], /* isOff */ rightType == GOAL_TYPE_OFF);

		mDrawables[:DataArea].setGoalValues(leftType, leftValues, rightType, rightValues);
	}

	function getValuesForGoalType(index, type) {
		var values = {
			:current => 0,
			:max => 1,
			:isValid => true,
			:staled => false
		};

		var app = App.getApp();
		var goalTypes = app.mGoalTypes;
		var info = ActivityMonitor.getInfo();

		switch(type) {
			case GOAL_TYPE_STEPS:
				values[:isValid] = false;
				if (Toybox has :Complications && mUseComplications) {
					var tmpValue = goalTypes[index].get("ComplicationValue");
					if (tmpValue != null) {
						values[:current] = tmpValue.toNumber();
						values[:isValid] = true;
					}
				}
				if (values[:isValid] == false) { // ignore steps (but get the max value) if we have Complication
					values[:current] = info.steps;
				}
				values[:max] = info.stepGoal;
				values[:isValid] = true;
				break;

			case GOAL_TYPE_FLOORS_CLIMBED:
				values[:isValid] = false;
				if (Toybox has :Complications && mUseComplications) {
					var tmpValue = goalTypes[index].get("ComplicationValue");
					if (tmpValue != null) {
						values[:current] = tmpValue.toNumber();
						values[:isValid] = true;
					}
				}
				if (info has :floorsClimbed) {
					if (values[:isValid] == false) { // ignore floor climbs (but get the max value) if we have Complication
						values[:current] = info.floorsClimbed;
					}
					values[:max] = info.floorsClimbedGoal;
					values[:isValid] = true;
				} else {
					values[:isValid] = false;
				}
				break;

			case GOAL_TYPE_ACTIVE_MINUTES:
				if (info has :activeMinutesWeek) {
					values[:current] = info.activeMinutesWeek.total;
					values[:max] = info.activeMinutesWeekGoal;
				} else {
					values[:isValid] = false;
				}
				break;

			case GOAL_TYPE_BATTERY:
				// #8: floor() battery to be consistent.
				values[:current] = Math.floor(Sys.getSystemStats().battery);
				values[:max] = 100;
				break;

			// SG Addition
			case GOAL_TYPE_BODY_BATTERY:
				values[:isValid] = false;
				values[:max] = 100;

				if (Toybox has :Complications && mUseComplications) {
					var tmpValue = goalTypes[index].get("ComplicationValue");
					if (tmpValue != null) {
						values[:current] = tmpValue.toFloat();
						values[:isValid] = true;
					}
				}
				if (values[:isValid] == false && (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getBodyBatteryHistory)) {
					var bodyBattery = Toybox.SensorHistory.getBodyBatteryHistory({:period=>1});
					if (bodyBattery != null) {
						bodyBattery = bodyBattery.next();
					}
					if (bodyBattery !=null) {
						bodyBattery = bodyBattery.data;
					}
					if (bodyBattery != null && bodyBattery >= 0 && bodyBattery <= 100) {
						values[:current] = bodyBattery.toFloat();
						values[:isValid] = true;
					}
				}

				break;

			// SG Addition
			case GOAL_TYPE_STRESS_LEVEL:
				values[:isValid] = false;
				values[:max] = 100;

				if (Toybox has :Complications && mUseComplications) {
					var tmpValue = goalTypes[index].get("ComplicationValue");
					if (tmpValue != null) {
						values[:current] = tmpValue.toFloat();
						values[:isValid] = true;
					}
				}
				if (values[:isValid] == false && (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getStressHistory)) {
					var stressLevel = Toybox.SensorHistory.getBodyBatteryHistory({:period=>1});
					//DEBUG*/ var stressLevelDate = 0;

					if (stressLevel != null) {
						stressLevel = stressLevel.next();
					}
					if (stressLevel !=null) {
						//DEBUG*/ stressLevelDate = stressLevel.when.value();
						stressLevel = stressLevel.data;
					}

					if (stressLevel != null) {
						if (stressLevel >= 0 && stressLevel <= 100) {
							values[:current] = stressLevel.toFloat();
							values[:isValid] = true;
							gStressLevel = stressLevel;

							/*DEBUG var timeMoment = new Time.Moment(stressLevelDate);
							var clockTime = Gregorian.info(timeMoment, Time.FORMAT_SHORT);
							var dateStr = clockTime.day + " " + clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
							var logText = "stressLevel " + stressLevel + " stressLevelDate " + dateStr + " is GOOD";
							if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
								logMessage(logText);
								gStressLevelLogText = logText;
							}/**/
	 					} else if (gStressLevel != null) {
							values[:current] = gStressLevel.toFloat();
							values[:isValid] = true;
							values[:staled] = true;

							/*DEBUG var timeMoment = new Time.Moment(stressLevelDate);
							var clockTime = Gregorian.info(timeMoment, Time.FORMAT_SHORT);
							var logText = "stressLevel " + stressLevel + "is over limit, ignoring";
							if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
								logMessage(logText);
								gStressLevelLogText = logText;
							}/**/
						} else {
							/*DEBUG var logText = "stressLevel " + stressLevel + "is over limit and no StressHistory data found yet";
							if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
								logMessage(logText);
								gStressLevelLogText = logText;
							}/**/
						}
 					} else if (gStressLevel != null) {
						values[:current] = gStressLevel.toFloat();
						values[:isValid] = true;
						values[:staled] = true;

						/*DEBUG var timeMoment = new Time.Moment(stressLevelDate);
						var clockTime = Gregorian.info(timeMoment, Time.FORMAT_SHORT);
						var logText = "stressLevel " + gStressLevel + " IS staled";
						if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
							logMessage(logText);
							gStressLevelLogText = logText;
						}/**/
					} else {
						/*DEBUG var logText = "No StressHistory data found yet";
						if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
							logMessage(logText);
							gStressLevelLogText = logText;
						}/**/
					}
					//logMessage("stressLeve " + stressLevel + " count " + count + " keptCount " + keptCount + " stressLevelDate " + stressLevelDate);
				} else {
					/*DEBUG var logText = "No StressHistory Sensor found";
					if (gStressLevelLogText == null || logText.equals(gStressLevelLogText) == false) {
						logMessage(logText);
						gStressLevelLogText = logText;
					}/**/
				}

				break;

			case GOAL_TYPE_CALORIES:
				values[:current] = info.calories;

				// #123 Protect against null value returned by getProperty(). Trigger invalid goal handling code below.
				// Protect against unexpected type e.g. String.
				values[:max] = $.getIntProperty("CaloriesGoal", 2000);
				break;

			case GOAL_TYPE_OFF:
				values[:isValid] = false;
				break;
		}

		// #16: If user has set goal to zero, or negative (in simulator), show as invalid. Set max to 1 to avoid divide-by-zero
		// crash in GoalMeter.getSegmentScale().
		// Sanity check. I've seen weird Invalid Value and "System Error" in DataArea.setGoalValues:48 and :61. Make sure the data is valid
		if (values[:isValid] && (!(values[:max] instanceof Lang.Number || values[:max] instanceof Lang.Float) || values[:max] < 1)) {
			/*DEBUG*/ logMessage("values[:max] is invalid=" + values[:max]);
			values[:max] = 1;
			values[:isValid] = false;
		}
		if (values[:isValid] && (!(values[:current] instanceof Lang.Number || values[:current] instanceof Lang.Float))) {
			/*DEBUG*/ logMessage("values[:current] is invalid=" + values[:current]);
			values[:current] = 0;
			values[:isValid] = false;
		}

		return values;
	}

	// Set clipping region to previously-displayed seconds text only.
	// Clear background, clear clipping region, then draw new seconds.
	function onPartialUpdate(dc) {
		//Sys.println("onPartialUpdate()");
	
		mDataFields.update(dc, /* isPartialUpdate */ true);
		mTime.drawSeconds(dc, /* isPartialUpdate */ true);
	}

	/*
	// Called when this View is removed from the screen. Save the
	// state of this View here. This includes freeing resources from
	// memory.
	function onHide() {
	}
	*/

	// The user has just looked at their watch. Timers and animations may be started here.
	function onExitSleep() {
		mIsSleeping = false;

		//Sys.println("onExitSleep()");

		// If watch does not support per-second updates, AND HideSeconds property is false,
		// show seconds, and make move bar original width.
		var hideSeconds = $.getIntProperty("HideSeconds", 0);
		if ((!PER_SECOND_UPDATES_SUPPORTED && hideSeconds == 0) || hideSeconds == 1 ) {
			setHideSeconds(false);
		}

		// Rather than checking the need for background requests on a timer, or on the hour, easier just to check when exiting
		// sleep.
		if (CrystalApp has :checkPendingWebRequests) { // checkPendingWebRequests() can be excluded to save memory.
			//logMessage("onExitSleep:Wakeup and checkPendingWebRequests");
			App.getApp().checkPendingWebRequests();
		}
		
		if (mHasGarminWeather == true) { // Using the Garmin Weather stuff
			ReadWeather(false);
		}	

		// If watch requires burn-in protection, set flag to false when entering sleep.
		var settings = Sys.getDeviceSettings();
		if (settings has :requiresBurnInProtection && settings.requiresBurnInProtection) {
			mIsBurnInProtection = false;
			mBurnInProtectionChangedSinceLastDraw = true;
		}
	}

	// Terminate any active timers and prepare for slow updates.
	function onEnterSleep() {
		mIsSleeping = true;

		//Sys.println("onEnterSleep()");
		//Sys.println("Partial updates supported = " + PER_SECOND_UPDATES_SUPPORTED);

		// If watch does not support per-second updates, then hide seconds, and make move bar full width.
		// onUpdate() is about to be called one final time before entering sleep.
		// If HideSeconds property is true, do not wastefully hide seconds again (they should already be hidden).
		var hideSeconds = $.getIntProperty("HideSeconds", 0);
		if ((!PER_SECOND_UPDATES_SUPPORTED && hideSeconds == 0) || hideSeconds == 1) {
			setHideSeconds(true);
		}

		// If watch requires burn-in protection, set flag to true when entering sleep.
		var settings = Sys.getDeviceSettings();
		if (settings has :requiresBurnInProtection && settings.requiresBurnInProtection) {
			//DEBUG*/ logMessage("onEnterSleep with needing burning proctection");
			mIsBurnInProtection = true;
			mBurnInProtectionChangedSinceLastDraw = true;
		}

		Ui.requestUpdate();
	}

	function isSleeping() {
		return mIsSleeping;
	}

	function useComplications() {
		return mUseComplications;
	}

	function setHideSeconds(hideSeconds) {

		// #158 Venu 2.80 firmware crash: mIsBurnInProtection fails to be set in onEnterSleep(), hopefully because that function
		// is now not called at startup before entering sleep, rather than because requiresBurnInProtection is not set. mTime will
		// be null in always-on mode, so add additional safety check here.
		// TODO: If Venu is guaranteed to start in always-on mode, we could initialise mIsBurnInProtection to true if
		// requiresBurnInProtection is true.
		if (mIsBurnInProtection || (mTime == null)) {
			return;
		}

		mTime.setHideSeconds(hideSeconds);
		mDrawables[:MoveBar].setFullWidth(hideSeconds);
	}
}

class CrystalDelegate extends Ui.WatchFaceDelegate {
    private var mview as CrystalView;

    //! Constructor
    //! @param view The analog view
    public function initialize(view as CrystalView) {
        WatchFaceDelegate.initialize();
        mview = view;
    }

	public function onPress(clickEvent as Ui.ClickEvent) as Lang.Boolean {
		var co_ords = clickEvent.getCoordinates();
        /*DEBUG*/ logMessage("onPress called with x:" + co_ords[0] + ", y:" + co_ords[1]);

		// returns the complicationId within the boundingBoxes
		if (Toybox has :Complications && App.getApp().getView().useComplications()) {
			var complicationId = checkBoundingBoxes(co_ords);
			if (complicationId != null) {
	            Complications.exitTo(complicationId);
			}
		}
	}

	function checkBoundingBoxes(co_ords) {
		// First check the indicators
		var indicatorCount = $.getIntProperty("IndicatorCount", 1);
		var spacingX;
		var spacingY;
		var complicationIndex;
		var complicationId;

		if (indicatorCount > 0) {
			var indicators = mview.mDrawables[:Indicators];
			var locX = indicators[:locX];
			var locY = indicators[:locY];
			var batteryWidth = indicators[:mBatteryWidth];

			spacingY = indicators[:mSpacing];
			spacingX = batteryWidth * 2;
			locX -= (batteryWidth / 1.5).toNumber();
			if (indicatorCount == 1) {
				locY -= spacingY;
				spacingY *= 2;
			}
			else {
				locY -= spacingY / 2;
			}

			if (indicatorCount == 3) {
				complicationIndex = "Complication_I" + isWithin(co_ords[0], co_ords[1], locX, locY - spacingY, spacingX, spacingY, "1") + isWithin(co_ords[0], co_ords[1], locX, locY, spacingX, spacingY, "2") + isWithin(co_ords[0], co_ords[1], locX, locY + spacingY, spacingX, spacingY, "3");
			} else if (indicatorCount == 2) {
				complicationIndex = "Complication_I" + isWithin(co_ords[0], co_ords[1], locX, locY - spacingY / 2, spacingX, spacingY, "1") + isWithin(co_ords[0], co_ords[1], locX, locY + spacingY / 2, spacingX, spacingY, "2");
			} else if (indicatorCount == 1) {
				complicationIndex = "Complication_I" + isWithin(co_ords[0], co_ords[1], locX, locY, spacingX, spacingY, "1");
			}

			if (complicationIndex.equals("Complication_I") == false) {
				complicationId = Storage.getValue(complicationIndex);
			}

			//DEBUG*/ logMessage(complicationIndex + " = " + complicationId);
			if (complicationId != null) {
				return complicationId;
			}
		}
		
		// Check the fields
		var fieldCount = $.getIntProperty("FieldCount", 3);

		if (fieldCount > 0) {
			spacingX = Sys.getDeviceSettings().screenWidth / (2 * fieldCount);
			spacingY = Sys.getDeviceSettings().screenHeight / 4;

			var left = mview.mDataFields.mLeft;
			var right = mview.mDataFields.mRight;
			var top = mview.mDataFields.mTop;

			if (fieldCount == 3) {
				complicationIndex = "Complication_F" + isWithin(co_ords[0], co_ords[1], left - spacingX / 2, top - spacingY / 2, spacingX, spacingY, "1") + isWithin(co_ords[0], co_ords[1], (right + left) / 2 - spacingX / 2, top - spacingY /2, spacingX, spacingY, "2") + isWithin(co_ords[0], co_ords[1], right - spacingX / 2, top - spacingY / 2, spacingX, spacingY, "3");
			} else if (fieldCount == 2) {
				complicationIndex = "Complication_F" + isWithin(co_ords[0], co_ords[1], left + ((right - left) * 0.15) - spacingX / 2, top - spacingY / 2, spacingX, spacingY, "1") + isWithin(co_ords[0], co_ords[1], left + ((right - left) * 0.85) - spacingX / 2, top - spacingY / 2, spacingX, spacingY, "2");
			} else if (fieldCount == 1) {
				complicationIndex = "Complication_F" + isWithin(co_ords[0], co_ords[1], (right + left) / 2 - spacingX / 2, top - spacingY / 2, spacingX, spacingY, "1");
			}

			if (complicationIndex.equals("Complication_F") == false) {
				complicationId = Storage.getValue(complicationIndex);
			}

			//DEBUG*/ logMessage(complicationIndex + " = " + complicationId);
			if (complicationId != null) {
				return complicationId;
			}
		}

		// Check the goals
		spacingX = Sys.getDeviceSettings().screenWidth / 11;
		spacingY = Sys.getDeviceSettings().screenHeight / 6;

		var left = mview.mDrawables[:DataArea].mGoalIconLeftX - spacingX / 8;
		var right = mview.mDrawables[:DataArea].mGoalIconRightX + spacingX / 8;
		var y = mview.mDrawables[:DataArea].mGoalIconY - spacingY / 8;

		// spacing * 3 to give it more room so we can press on the text too.
		complicationIndex = "Complication_G" + isWithin(co_ords[0], co_ords[1], left, y, spacingX * 3, spacingY, "1") + isWithin(co_ords[0], co_ords[1], right - spacingX * 3, y, spacingX * 3, spacingY, "2");
		if (complicationIndex.equals("Complication_G") == false) {
			complicationId = Storage.getValue(complicationIndex);
		}

		//DEBUG*/ logMessage(complicationIndex + " = " + complicationId);
		if (complicationId != null) {
			return complicationId;
		}

		return null;
	}

	function isWithin(x, y, startX, startY, spacingX, spacingY, field) {
		if (x > startX && x < startX + spacingX && y > startY and y < startY + spacingY) {
			/*DEBUG*/ logMessage("True:  " + x + "/" + y + " is within " + startX + "/" + startY + " and " + (startX + spacingX).toString() + "/" + (startY + spacingY).toString());
			return field;
		}
		else {
			/*DEBUG*/ logMessage("False:  " + x + "/" + y + " is NOT within " + startX + "/" + startY + " and " + (startX + spacingX).toString() + "/" + (startY + spacingY).toString());
			return "";
		}
	}

    //! The onPowerBudgetExceeded callback is called by the system if the
    //! onPartialUpdate method exceeds the allowed power budget. If this occurs,
    //! the system will stop invoking onPartialUpdate each second, so we notify the
    //! view here to let the rendering methods know they should not be rendering a
    //! second hand.
    //! @param powerInfo Information about the power budget
    public function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        //DEBUG*/ logMessage("Average execution time: " + powerInfo.executionTimeAverage);
        //DEBUG*/ logMessage("Allowed execution time: " + powerInfo.executionTimeLimit);
		//mview.turnPartialUpdatesOff();
    }
}

/*
function type_name(obj) {
    if (obj instanceof Toybox.Lang.Number) {
        return "Number";
    } else if (obj instanceof Toybox.Lang.Long) {
        return "Long";
    } else if (obj instanceof Toybox.Lang.Float) {
        return "Float";
    } else if (obj instanceof Toybox.Lang.Double) {
        return "Double";
    } else if (obj instanceof Toybox.Lang.Boolean) {
        return "Boolean";
    } else if (obj instanceof Toybox.Lang.String) {
        return "String";
    } else if (obj instanceof Toybox.Lang.Array) {
        var s = "Array [";
        for (var i = 0; i < obj.size(); ++i) {
            s += type_name(obj);
            s += ", ";
        }
        s += "]";
        return s;
    } else if (obj instanceof Toybox.Lang.Dictionary) {
        var s = "Dictionary{";
        var keys = obj.keys();
        var vals = obj.values();
        for (var i = 0; i < keys.size(); ++i) {
            s += keys;
            s += ": ";
            s += vals;
            s += ", ";
        }
        s += "}";
        return s;
    } else if (obj instanceof Toybox.Time.Gregorian.Info) {
        return "Gregorian.Info";
    } else {
        return "???";
    }
}
*/