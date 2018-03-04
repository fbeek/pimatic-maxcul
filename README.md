pimatic-maxcul
=======================

Pimatic plugin to control MAX! home heating devices with a Busware CUL868 usb wireless stick.

At the moment the software is at a stable stage but please use it with caution.

If you have questions have look at the Issue and Pull Request area on our Github repository or ask a question in the pimatic forum.

Information
---------

Because of the support ending for pimatic 0.8.x, we only support pimatic > 0.9.x !

Usage
---------

If device discovery is activated in the device section of pimatic,
the maxcul plugin automatically detects incoming pairing messages for 20 seconds and reacts accordingly.
New paired devices are displayed in the discovery overview.

**Group support:**
All devices support groups. If a group is defined, the command is sent to the device but all devices in the same group react to it.

**Pairing support:**
Devices can be connected to each other. Pairing must be done reciprocally.
To revoke the paring a facotry reset must be done.

**Fake devices:**
There are two types of fake devices.
- **Fake shutter device:**
  The shutter has a optional refContact parameter.
  You can define here a boolean variable expression.  

- **Fake wall thermostat device:**
  A reference temperature variable "refTemp" (expression) *must*
  be defined in the configuration.

**Config transfer button:**
All devices have a config tranfer button.
The general config but also the group ID and pair IDs are sent to the device using the config tranfer button.
After the configuration is finished, the button can be removed from the gui.

---------------

Example plugin configuration

    {
      "plugin": "maxcul",
      "serialPortName": "/dev/ttyACM0",
      "homebaseAddress": "123456",
      "baudrate": 9600
    }

---------------

Example device configuration shutter contact

    {
      "id": "shutter-1",
      "class": "MaxculShutterContact",
      "name": "Shutter Contact 1",
      "deviceId": "020BFF",
      "groupId": "02",
      "pairIds": [
         {
           "pairId": "0D0CF6",
           "type": "HeatingThermostat"
         },
         {
           "pairId": "178ab2",
           "type": "WallMountedThermostat"
         }
       ]
    }

---------------

Example device configuration fake shutter contact

    {
      "id": "fake-shutter-2",
      "name": "Fake shutter contact 2",
      "class": "MaxculFakeShutterContact",
      "deviceId": "232323",
      "groupId": "02",
      "pairIds": [
        {
          "pairId": "0D0CF6",
          "type": "HeatingThermostat"
        },
        {
          "pairId": "178ab2",
          "type": "WallMountedThermostat"
        }
      ],
      "refContact": "$contact-kitchen-door.contact"
    }

"$contact-kitchen-door.contact" is for example a HomeduinoRFContactSensor.

---------------

Example device configuration push button

    {
      "id": "button-1",
      "class": "MaxculPushButton",
      "name": "Push Button 1",
      "deviceId": "03f92a",
      "groupId": "03",
      "pairIds": []      
    }

---------------

Example device configuration wall thermostat

    {
      "id": "wallthermostat-01",
      "class": "MaxculWallThermostat",
      "name": "WallThermostat 1",
      "deviceId": "178ab2",
      "groupId": "02",
      "guiShowModeControl": true,
      "guiShowPresetControl": true,
      "guiShowTemperatureInput": true,
      "guiShowMeasuredTemperature": true,
      "guiShowBatteryState": true,
      "guiShowConfigButton": true,
      "ecoTemp": 17,
      "comfyTemp": 20,
      "minimumTemperature": 4.5,
      "maximumTemperature": 30.5,
      "measurementOffset": 0,
      "windowOpenTime": 60,
      "windowOpenTemperature": 4.5,
      "pairIds": [
        {
          "pairId": "232323",
          "type": "ShutterContact"
        },
        {
          "pairId": "0D0CF6",
          "type": "HeatingThermostat"
        }
      ]
    }

---------------

Example device configuration fake wall thermostat

    {
      "id": "fakewallthermostat-02",
      "class": "MaxculFakeWallThermostat",
      "name": "FakeWallThermostat 2",
      "deviceId": "343434",
      "groupId": "02",
      "guiShowModeControl": true,
      "guiShowPresetControl": true,
      "guiShowTemperatureInput": true,
      "guiShowMeasuredTemperature": true,
      "guiShowBatteryState": true,
      "guiShowConfigButton": true,
      "ecoTemp": 17,
      "comfyTemp": 20,
      "refTemp": "$tempsensor.temperature",
      "minimumTemperature": 4.5,
      "maximumTemperature": 30.5,
      "measurementOffset": 0,
      "windowOpenTime": 60,
      "windowOpenTemperature": 4.5,
      "pairIds": [
        {
          "pairId": "232323",
          "type": "ShutterContact"
        },
        {
          "pairId": "0D0CF6",
          "type": "HeatingThermostat"
        }
      ]
    }

"$tempsensor.temperature" is for example a room temperature variable.

---------------

Example device configuration heating thermostat

    {
      "id": "heatingthermostat-01",
      "class": "MaxculHeatingThermostat",
      "name": "Thermostat 1",
      "deviceId": "0D0CF6",
      "groupId": "02",
      "guiShowModeControl": true,
      "guiShowPresetControl": true,
      "guiShowTemperatureInput": true,
      "guiShowMeasuredTemperature": true,
      "guiShowBatteryState": true,
      "guiShowConfigButton": true,
      "guiShowValvePosition": true,
      "ecoTemp": 17,
      "comfyTemp": 20,
      "minimumTemperature": 4.5,
      "maximumTemperature": 30.5,
      "measurementOffset": 0,
      "windowOpenTime": 60,
      "windowOpenTemperature": 4.5,
      "pairIds": [
        {
          "pairId": "232323",
          "type": "ShutterContact"
        },
        {
          "pairId": "178ab2",
          "type": "WallMountedThermostat"
        }
      ],
    }

---------------


### Sponsoring

Do you like this plugin? Then please consider a donation to support the development.

<span class="badge-paypal"><a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=ZSZE2U9Z6J26U" title="Donate to this project using Paypal"><img src="https://img.shields.io/badge/paypal-donate-yellow.svg" alt="PayPal Donate Button" /></a></span>

<a href="https://flattr.com/submit/auto?fid=jeo2wl&url=https%3A%2F%2Fgithub.com%2Ffbeek%2Fpimatic-maxcul" target="_blank"><img src="http://button.flattr.com/flattr-badge-large.png" alt="Flattr this" title="Flattr this" border="0"></a>

Changelog
---------------

* v0.1.0

    This first Version enables the user to receive messages from the MAX! devices. It receives the
messages, decodes them and prints them to the console or log as debugging information.

* v0.2.0

    This version enables you to pair the max shutter contacts with the pimatic system and use them as
sensor. Also you can pair the heating thermostats so that they can get the time informations from the
pimatic system and set the mode (auto/boost/manuel) and switch between the comfy and eco temperature.

* v0.2.5

    This Version enables the user to use the thermostat heating elements. You can now set the desired temperature, the mode, show the battery state and the measured temperature in the pimatic frontend.

* v0.2.9

    Now you can disable or enable the pair feature. So you can lock your system against foreign devices.

* v0.3.0

    There is now an "off"-Button so that we can set the heating thermostat to off with one click. Also there is now a better input checking for the temperature input with an info message if the input is out of range. The input must be between 4.5 (off) and 30.5 (full on).

* v0.3.1

    Fixed a bug which prevents the shutter contacts from updating.

* v0.4.0

    You can now define some default values for each heating thermostat that can be written wirelessly to the device itself. So you can set a min and max temperature in the device. If this is set, a user can only set a value between these values if he is setting the temperature physically on the device itself. You can set this value in the device config and enable a transmit button in the frontend. If this is clicked the data where transferred to the device. Also this version fixed a bug which sets the shutter contact to a wrong value.

* v0.4.1

    Fixed a wrong type for an initial variable value.

* v0.5.0

    Added rewritten communication layer with retransmit, timeout and promise support for a better reliability. Also cleaned up the code.
    Disabled the "auto" mode button, because there is no support to config this mode at the moment.

* v0.5.1

    Added Missing Class file.

* v0.5.2

    Removed the HiPack dependency, this npm package is no longer developed and so we need to remove it for the further development of the pimatic 0.9 compatibility.
    We also changed the serial port timeouts and logging levels for a better user experience.

* v0.9.0

    First Version with pimatic 0.9 support. This Version is not compatible with 0.8 anymore because we raised the version of the node-serialport module, version 0.8 users use
    maxcul v0.5.2 please instead.

* v0.9.1

    Added debug flag to give the user the possibility to enable debugging messages. Also we hardened the plugin against crashes if there is problem with the serialport.

* v0.9.2

    Smaller Bugfixes and optimizations.

* v0.9.3

    Added a RSSI reporting of received pakages to the debugging messages to check the wireless connection quality. Also smaller bugfixes and optimizations.

* v0.9.4

    Added EcoButton support. Special THANKS to w3stbam for implementing this feature.

* v0.9.5

    Added support for displaying the valve position in the frontend. Also fixed a bug with the battery states of the heating thermostats. Special THANKS to treban for supporting this features.

* v0.9.6

    Major Bugfixes

* v0.9.7

    removed some typos (Rootie)

* v0.9.8

    Added LOVF handling (Rootie)

* v1.0.0

    Big Thanks to Treban for implementing device discovery, WallThermostat / Fake Wall-Thermostat Support, Fake Shutter-Device, support for pairing devices to each other, support for groupIds and fixing #22 and #12

* v1.0.1

    Updated Bitset module to fix Issue #31

* v1.0.2

    Fixed wrong module name. THX to mwittig for reporting an fixing.

* v1.0.3
  
    Fixed broken function call #33

* v1.0.4

    Fixed a bug in the mode handling #34 and added a default value for the battery state of the shutter contact

* v1.0.5

    Cleanup

* v1.0.6

    Fixed #36 by making the Wall-Thermostat WindowOpenTemperature configurable

THX for development Support:
-------
* Rootie
* Treban
* Mwittig

THX for donations:
-------
* L. Bellwald

ToDo
-------
* CUL Credit System support to respect the ISM Band 1% Rules
* Support for programming Week Profile (at the moment there is only the default program in "Auto Mode")
* Implement ConfigValve support to configure the boost duration
