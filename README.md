# ASL3 Saytime Weather TimeFormat

Top-of-the-hour spoken time and current weather conditions for AllStarLink 3 on Debian 12 Bookworm and Debian 13 Trixie.

This version keeps the nostalgic recorded `.gsm` voice-file behavior from the earlier KD5FMU Saytime/Weather projects, while adding selectable 12-hour or 24-hour time.

## What it does

- Announces current time and WeatherAPI.com current conditions.
- ## Supports 12-hour or 24-hour time.
- Uses the recorded voice files downloaded from the original sound file package.
- Stores sound files in the same custom sound location used by the previous repos:

```bash
/usr/local/share/asterisk/sounds/custom
```

- Uses WeatherAPI.com current weather data.
- Installs a systemd service and timer to keep weather data cached.
- Adds an editable root crontab block for hourly announcements.
- Handles multi-word WeatherAPI.com conditions such as `Partly Cloudy`, `Light Rain`, and `Patchy Rain Nearby` by trying to speak each available word in order.

## Watch this video to get your WeatherAPI.com API Key

[![Watch the video](https://img.youtube.com/vi/B-R4uuhnt8Q/hqdefault.jpg)](https://www.youtube.com/watch?v=B-R4uuhnt8Q)


## Install

Download the installer from your new GitHub repo after publishing it:

```bash
sudo wget https://raw.githubusercontent.com/KD5FMU/Saytime-Weather-TimeFormat-ASL3/refs/heads/main/install_asl3_saytime_weather_timeformat.sh
```
then we need to make it executable
```
sudo chmod +x install_asl3_saytime_weather_timeformat.sh
```
And then we can run the installer
```
sudo ./install_asl3_saytime_weather_timeformat.sh
```

Optional install with location, node, and time format:

```bash
sudo ./install_asl3_saytime_weather_timeformat.sh 74437 58176 12
```

or:

```bash
sudo ./install_asl3_saytime_weather_timeformat.sh 74437 58176 24
```

## Configure

Edit the config file:

```bash
sudo nano /etc/asterisk/local/weatherapi.ini
```

Set these values:

```bash
API_KEY="your_weatherapi_key"
LOCATION="74437"
NODE="58176"
TIME_FORMAT="12"
```

`LOCATION` may be a ZIP code, airport code, city, or airport name supported by WeatherAPI.com.

Examples:

```bash
LOCATION="74437"
LOCATION="Henryetta OK"
LOCATION="KTUL"
LOCATION="Tulsa International Airport"
```

## Test WeatherAPI.com cache

```bash
sudo /usr/local/sbin/asl3-weatherapi-update.sh
/usr/local/sbin/show_weatherapi.sh
```

## Test the spoken announcement

Using config values:

```bash
sudo /usr/bin/perl /usr/local/sbin/saytime.pl
```

Using command-line values:

```bash
sudo /usr/bin/perl /usr/local/sbin/saytime.pl 74437 58176 12
```

or:

```bash
sudo /usr/bin/perl /usr/local/sbin/saytime.pl 74437 58176 24
```

## Crontab

The installer adds an editable root crontab block.

Open it with:

```bash
sudo crontab -e
```

Example hourly line:

```bash
0 * * * * /usr/bin/nice -19 /usr/bin/perl /usr/local/sbin/saytime.pl 74437 58176 >/dev/null 2>&1
```

Time format is controlled in:

```bash
/etc/asterisk/local/weatherapi.ini
```

Set:

```bash
TIME_FORMAT="12"
```

or:

```bash
TIME_FORMAT="24"
```

## WeatherAPI.com service/timer

Weather cache updates are handled by systemd:

```bash
systemctl status asl3-weatherapi-update.timer
systemctl status asl3-weatherapi-update.service
```

## Uninstall
- if you feel you want to uninstall this setup then download this script
```
https://raw.githubusercontent.com/KD5FMU/Saytime-Weather-TimeFormat-ASL3/refs/heads/main/uninstaller_remove_audio_files.sh
```
And then make it executable
```
sudo chmod +x uninstaller_remove_audio_files.sh
```
And then run the file
```
sudo ./uninstaller_remove_audio_files.sh
```

## Notes

- If Supermon changes or overwrites sound/script locations later, rerun the installer.
- This script expects Asterisk/ASL3 local playback to be available through:

```bash
/usr/sbin/asterisk -rx "rpt localplay NODE /tmp/current-time"
```

73!

## License

This project is licensed under the GNU 3.0 General Public License.

By submitting a contribution to this repository, you agree that your contribution is licensed under the same MIT License.
