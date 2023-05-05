using Toybox.Background as Bg;
using Toybox.System as Sys;
using Toybox.Communications as Comms;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Application.Storage;
using Toybox.Application.Properties;

(:background)
class BackgroundService extends Sys.ServiceDelegate {
	var _teslaInfo;
	var _accessToken;
	var _vehicle_id;
	var _fromVehicleState;

	(:background)
	function initialize() {
		Sys.ServiceDelegate.initialize();

//****************************************************************
//******** REMVOVED THIS SECTION IF TESLA CODE NOT WANTED ********
//****************************************************************
		if (Storage.getValue("Tesla") == null) {
			return;
		}

		_teslaInfo = {};

		// See if we should try to refresh our access token
		var accessToken = $.getStringProperty("TeslaAccessToken","");

		var createdAt = Storage.getValue("TeslaTokenCreatedAt");
		if (createdAt == null) {
			createdAt = 0;
		}

		var expiresIn = Storage.getValue("TeslaTokenExpiresIn");
		if (expiresIn == null) {
			expiresIn = 0;
		}
		
		var timeNow = Time.now().value();
		var interval = 5 * 60;
		var notExpired = (timeNow + interval < createdAt + expiresIn);

		if (accessToken != null && accessToken.equals("") == false && notExpired == true) {
//2023-03-05 var expireAt = new Time.Moment(createdAt + expiresIn);
//2023-03-05 var clockTime = Gregorian.info(expireAt, Time.FORMAT_MEDIUM);
//2023-03-05 var dateStr = clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
//2023-03-05 logMessage("initialize:Using token '" + accessToken.substring(0,10) + "...' which expires at " + dateStr);
			_accessToken = "Bearer " + accessToken;
			_vehicle_id = Storage.getValue("TeslaVehicleID");
		}
//****************************************************************
//******************** END OF REMVOVED SECTION *******************
//****************************************************************
	}

	// Read pending web requests, and call appropriate web request function.
	// This function determines priority of web requests, if multiple are pending.
	// Pending web request flag will be cleared only once the background data has been successfully received.
	(:background)
	function onTemporalEvent() {
		var pendingWebRequests = Storage.getValue("PendingWebRequests");
		//2023-03-05 logMessage("onTemporalEvent:PendingWebRequests is '" + pendingWebRequests + "'");
		if (pendingWebRequests != null) {

			// 1. City local time.
			if (pendingWebRequests["CityLocalTime"] != null) {
				makeWebRequest(
					"https://script.google.com/macros/s/AKfycbwPas8x0JMVWRhLaraJSJUcTkdznRifXPDovVZh8mviaf8cTw/exec",
					{
						"city" => $.getStringProperty("LocalTimeInCity","")
					},
					method(:onReceiveCityLocalTime)
				);

			} 

			// 2. Weather.
			if (pendingWebRequests["OpenWeatherMapCurrent"] != null) {
				var owmKeyOverride = $.getStringProperty("OWMKeyOverride","");
				var lat = $.getStringProperty("LastLocationLat","");
				var lon = $.getStringProperty("LastLocationLng","");

				if (lat != null && lon != null) {
					makeWebRequest(
						"https://api.openweathermap.org/data/2.5/weather",
						{
							"lat" => lat,
							"lon" => lon,

							// Polite request from Vince, developer of the Crystal Watch Face:
							//
							// Please do not abuse this API key, or else I will be forced to make thousands of users of Crystal
							// sign up for their own Open Weather Map free account, and enter their key in settings - a much worse
							// user experience for everyone.
							//
							// Crystal has been registered with OWM on the Open Source Plan, which lifts usage limits for free, so
							// that everyone benefits. However, these lifted limits only apply to the Current Weather API, and *not*
							// the One Call API. Usage of this key for the One Call API risks blocking the key for everyone.
							//
							// If you intend to use this key in your own app, especially for the One Call API, please create your own
							// OWM account, and own key. You should be able to apply for the Open Source Plan to benefit from the same
							// lifted limits as Crystal. Thank you.
							"appid" => ((owmKeyOverride == null) || (owmKeyOverride.length() == 0)) ? "2651f49cb20de925fc57590709b86ce6" : owmKeyOverride,

							"units" => "metric" // Celcius.
						},
						method(:onReceiveOpenWeatherMapCurrent)
					);
				}
			}

//****************************************************************
//******** REMVOVED THIS SECTION IF TESLA CODE NOT WANTED ********
//****************************************************************
			// 3. Tesla
			if (pendingWebRequests["TeslaInfo"] != null && Storage.getValue("Tesla") != null) {
				if (!Sys.getDeviceSettings().phoneConnected) {
					return;
				}

				if (_accessToken != null) {
					// We seem to have an unexpired access token, try to get our data, or at least our vehicles
					if (_vehicle_id == null) {
						_fromVehicleState = false;
						/*DEBUG*/ logMessage("Requesting vehicles from temporalEvent");
						makeTeslaWebRequest("https://" + $.getStringProperty("TeslaServerAPILocation","") + "/api/1/vehicles", null, method(:onReceiveVehicles));
					}
					else {
						/*DEBUG*/ logMessage("Requesting vehicle data from temporalEvent");
						makeTeslaPlainWebRequest("https://" + $.getStringProperty("TeslaServerAPILocation","") + "/api/1/vehicles/" + _vehicle_id + "/vehicle_data", null, method(:onReceiveVehicleData));
					}
				}
				else { // We need to try to get a new token
					//2023-03-05 logMessage("initialize:Generating Access Token");
					var refreshToken = $.getStringProperty("TeslaRefreshToken","");
					if (refreshToken != null) {
						_fromVehicleState = false;
						/*DEBUG*/ logMessage("Requesting access token from temporalEvent");
						makeTeslaWebPost(refreshToken, method(:onReceiveToken));
					} else {
						/*DEBUG*/ logMessage("No refresh token");
					}
				}
			}
//****************************************************************
//******************** END OF REMVOVED SECTION *******************
//****************************************************************
		} /* else {
			Sys.println("onTemporalEvent() called with no pending web requests!");
		} */
	}

	// Sample time zone data:
	/*
	{
	"requestCity":"london",
	"city":"London",
	"current":{
		"gmtOffset":3600,
		"dst":true
		},
	"next":{
		"when":1540688400,
		"gmtOffset":0,
		"dst":false
		}
	}
	*/

	// Sample error when city is not found:
	/*
	{
	"requestCity":"atlantis",
	"error":{
		"code":2, // CITY_NOT_FOUND
		"message":"City \"atlantis\" not found."
		}
	}
	*/
	(:background)
	function onReceiveCityLocalTime(responseCode, data) {

		// HTTP failure: return responseCode.
		// Otherwise, return data response.
		if (responseCode != 200) {
			data = {
				"httpError" => responseCode
			};
		}

		Bg.exit({
			"CityLocalTime" => data
		});
	}

	// Sample invalid API key:
	/*
	{
		"cod":401,
		"message": "Invalid API key. Please see http://openweathermap.org/faq#error401 for more info."
	}
	*/

	// Sample current weather:
	/*
	{
		"coord":{
			"lon":-0.46,
			"lat":51.75
		},
		"weather":[
			{
				"id":521,
				"main":"Rain",
				"description":"shower rain",
				"icon":"09d"
			}
		],
		"base":"stations",
		"main":{
			"temp":281.82,
			"pressure":1018,
			"humidity":70,
			"temp_min":280.15,
			"temp_max":283.15
		},
		"visibility":10000,
		"wind":{
			"speed":6.2,
			"deg":10
		},
		"clouds":{
			"all":0
		},
		"dt":1540741800,
		"sys":{
			"type":1,
			"id":5078,
			"message":0.0036,
			"country":"GB",
			"sunrise":1540709390,
			"sunset":1540744829
		},
		"id":2647138,
		"name":"Hemel Hempstead",
		"cod":200
	}
	*/
	(:background)
	function onReceiveOpenWeatherMapCurrent(responseCode, data) {
		var result;
		
		// Useful data only available if result was successful.
		// Filter and flatten data response for data that we actually need.
		// Reduces runtime memory spike in main app.
		if (responseCode == 200) {
			result = {
				"cod" => data["cod"],
				"lat" => data["coord"]["lat"],
				"lon" => data["coord"]["lon"],
				"dt" => data["dt"],
				"temp" => data["main"]["temp"],
				"humidity" => data["main"]["humidity"],
				"icon" => data["weather"][0]["icon"]
			};

		// HTTP error: do not save.
		} else {
			result = Storage.getValue("OpenWeatherMapCurrent");
			if (result) {
				result["cod"] = responseCode;
			} else {
				result = {
					"httpError" => responseCode
				};
			}

			/*var clockTime = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
			var dateStr = clockTime.year + " " + clockTime.month + " " + clockTime.day + " " + clockTime.hour + ":" + clockTime.min.format("%02d") + ":" + clockTime.sec.format("%02d");
			Sys.println(dateStr + " : httpError=" + responseCode);*/
		}

		Bg.exit({
			"OpenWeatherMapCurrent" => result
		});
	}

//****************************************************************
//******** REMVOVED THIS SECTION IF TESLA CODE NOT WANTED ********
//****************************************************************
	(:background)
    function onReceiveToken(responseCode, data) {
		/*DEBUG*/ logMessage("onReceiveToken: " + responseCode);
		//logMessage("onReceiveToken data  is " + data);
		/*var teslaInfo = {};/* = Storage.getValue("TeslaInfo");
		if (teslaInfo == null) {
			teslaInfo = {};
		}*/

        if (responseCode == 200) {
			_teslaInfo.put("AccessToken", data["access_token"]);
			_teslaInfo.put("RefreshToken", data["refresh_token"]);
			_teslaInfo.put("TokenExpiresIn", data["expires_in"]);
			_teslaInfo.put("TokenCreatedAt", Time.now().value());

			_accessToken = "Bearer " + data["access_token"];

			/*DEBUG*/ logMessage("Requesting vehicles from onReceiveToken");
			makeTeslaWebRequest("https://" + $.getStringProperty("TeslaServerAPILocation","") + "/api/1/vehicles", null, method(:onReceiveVehicles));
        } else {
			_teslaInfo.put("httpErrorTesla", responseCode);
			Bg.exit({ "TeslaInfo" => _teslaInfo });
	    }
    }

	(:background)
    function onReceiveVehicles(responseCode, data) {
		/*DEBUG*/ logMessage("onReceiveVehicles: " + responseCode);
		//2023-03-05 logMessage("onReceiveVehicles responseCode is " + responseCode + " with data " + data);
		/*var teslaInfo = {};/* = Storage.getValue("TeslaInfo");
		if (teslaInfo == null) {
			teslaInfo = {};
		}*/

        if (responseCode == 200) {
            var vehicles = data.get("response");
            if (vehicles.size() > 0) {
                _vehicle_id = vehicles[0].get("id");
                _teslaInfo.put("VehicleID", _vehicle_id);
				_teslaInfo.put("VehicleState", vehicles[0].get("state"));

				if (!_fromVehicleState) {
					/*DEBUG*/ logMessage("Requesting vehicle data from onReceiveVehicles");
					makeTeslaPlainWebRequest("https://" + $.getStringProperty("TeslaServerAPILocation","") + "/api/1/vehicles/" + _vehicle_id + "/vehicle_data", null, method(:onReceiveVehicleData));
					return;
				}
	        } else {
				_teslaInfo.put("VehicleState", "No Vehicle");
		    }
        } else {
			_vehicle_id = 0;
            _teslaInfo.put("VehicleID", _vehicle_id);
			_teslaInfo.put("VehicleState", "Error " + responseCode);
			_teslaInfo.put("httpErrorTesla", responseCode);
	    }
		Bg.exit({ "TeslaInfo" => _teslaInfo });
    }

	(:background)
    function onReceiveVehicleData(responseCode, responseData) {
		/*DEBUG*/ logMessage("onReceiveVehicleData: " + responseCode);
		/*var teslaInfo = {};/* = Storage.getValue("TeslaInfo");
		if (teslaInfo == null) {
			teslaInfo = {};
		}*/

		_teslaInfo.put("httpErrorTesla", responseCode);
        /*DEBUG*/ var myStats = System.getSystemStats();
        /*DEBUG*/ logMessage("Total memory: " + myStats.totalMemory + " Used memory: " + myStats.usedMemory + " Free memory: " + myStats.freeMemory);

		//2023-03-05 logMessage("onReceiveVehicleData responseCode is " + responseCode);
        if (responseCode == 200) {
			if (responseData instanceof Lang.String) {
				_teslaInfo.put("VehicleState", "online");

				var pos = responseData.find("battery_level");
				var str = responseData.substring(pos + 15, pos + 20);
				var posEnd = str.find(",");
				_teslaInfo.put("BatteryLevel", $.validateNumber(str.substring(0, posEnd), 0));

				pos = responseData.find("charging_state");
				str = responseData.substring(pos + 17, pos + 37);
				posEnd = str.find("\"");
				_teslaInfo.put("ChargingState", $.validateString(str.substring(0, posEnd), ""));

				pos = responseData.find("inside_temp");
				str = responseData.substring(pos + 13, pos + 20);
				posEnd = str.find(",");
				_teslaInfo.put("InsideTemp", $.validateNumber(str.substring(0, posEnd), 0));

				pos = responseData.find("sentry_mode");
				str = responseData.substring(pos + 13, pos + 20);
				posEnd = str.find(",");
				_teslaInfo.put("SentryEnabled", $.validateString(str.substring(0, posEnd), "false").equals("true"));

				pos = responseData.find("preconditioning_enabled");
				str = responseData.substring(pos + 25, pos + 32);
				posEnd = str.find(",");
				_teslaInfo.put("PrecondEnabled", $.validateString(str.substring(0, posEnd), "false").equals("true"));
			}
			else {
				var response = data.get("response");
				if (response != null) {
					_teslaInfo.put("VehicleState", "online");

					var result = response.get("charge_state");
					if (result != null) {
						_teslaInfo.put("BatteryLevel", result.get("battery_level"));
						_teslaInfo.put("ChargingState", result.get("charging_state"));
						_teslaInfo.put("PrecondEnabled", result.get("preconditioning_enabled"));
					}
					result = response.get("climate_state");
					if (result != null) {
						_teslaInfo.put("InsideTemp", result.get("inside_temp"));
					}	        	
					
					result = response.get("vehicle_state");
					if (result != null) {
						_teslaInfo.put("SentryEnabled", result.get("sentry_mode"));
					}	        	
				}
			}
		// If Tesla can't find our vehicle by its ID, reset it and maybe we'll have better luck next time
        } else if (responseCode == 404 || responseCode == 408) {
			if (responseCode == 404) {
				_teslaInfo.put("VehicleID", 0);
				_vehicle_id = 0;
			}
			_fromVehicleState = true;
			/*DEBUG*/ logMessage("Requesting vehicles from onReceiveVehicleData");
			makeTeslaWebRequest("https://" + $.getStringProperty("TeslaServerAPILocation","") + "/api/1/vehicles", null, method(:onReceiveVehicles));
			return;
	    }
		// Our access token has expired, ask for a new one
		else if (responseCode == 401) {
			var refreshToken = $.getStringProperty("TeslaRefreshToken","");
			if (refreshToken != null) {
				_fromVehicleState = true;
				/*DEBUG*/ logMessage("Requesting access token from onReceiveVehicleData");
				makeTeslaWebPost(refreshToken, method(:onReceiveToken));
				return;
			}
		}

		Bg.exit({ "TeslaInfo" => _teslaInfo });
    }

	(:background)
    function makeTeslaWebPost(token, notify) {
        var url = "https://" + $.getStringProperty("TeslaServerAUTHLocation","") + "/oauth2/v3/token";
        Comms.makeWebRequest(
            url,
            {
				"grant_type" => "refresh_token",
				"client_id" => "ownerapi",
				"refresh_token" => token,
				"scope" => "openid email offline_access"
            },
            {
                :method => Comms.HTTP_REQUEST_METHOD_POST,
                :responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            notify
        );
    }

	(:background)
    function makeTeslaWebRequest(url, params, callback) {
		var options = {
            :method => Comms.HTTP_REQUEST_METHOD_GET,
            :headers => {
              		"Authorization" => _accessToken,
					"User-Agent" => "Crystal-Tesla for Garmin",
					},
            :responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
		//2023-03-05 logMessage("makeWebRequest url: '" + url + "'");
		Comms.makeWebRequest(url, params, options, callback);
    }

	(:background)
    function makeTeslaPlainWebRequest(url, params, callback) {
		var options = {
            :method => Comms.HTTP_REQUEST_METHOD_GET,
            :headers => {
              		"Authorization" => _accessToken,
					"User-Agent" => "Crystal-Tesla for Garmin",
					},
            :responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
		//2023-03-05 logMessage("makeWebRequest url: '" + url + "'");
		Comms.makeWebRequest(url, params, options, callback);
    }
//****************************************************************
//******************** END OF REMVOVED SECTION *******************
//****************************************************************

	(:background)
	function makeWebRequest(url, params, callback) {
		var options = {
			:method => Comms.HTTP_REQUEST_METHOD_GET,
			:headers => {
					"Content-Type" => Comms.REQUEST_CONTENT_TYPE_URL_ENCODED},
			:responseType => Comms.HTTP_RESPONSE_CONTENT_TYPE_JSON
		};
		Comms.makeWebRequest(url, params, options, callback);
	}
}
