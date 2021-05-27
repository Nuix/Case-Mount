# Case-Mount


[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0) ![This script was last tested in Nuix 8.2](https://img.shields.io/badge/Script%20Tested%20in%20Nuix-9.2-green.svg)

View the GitHub project [here](https://github.com/Nuix/Case-Mount) or download the latest release [here](https://github.com/Nuix/Case-Mount/releases).

**Written By:** Cameron Stiller

# Overview
Display your Nuix selected case items as a drive letter (windows). This script when run will mount a drive letter representing the items you have selected. Using the Metadata Profile selected the paths will be calculated ready for your browsing needs. Due to the lack of SSL certificate office products may state that they can not access products however you can copy the files off and open them from another location.

![Drive letter](https://raw.githubusercontent.com/Nuix/Case-Mount/main/images/webDav%20Nuix%20drive.png)

## Why would you want to do this?

Consider the topic of Antivirus scanning over binaries. When antivirus is run over a drive mount and any items deleted they will be excluded in your original case with the reason 'deleted'.

Another story could be to make an 'instant export'. You could check out your production set numbering based on the natives if you metadata profile was Document Set IDs

Yet another example could be organising photo's by their Exif:

![Exif Example](https://github.com/Nuix/Case-Mount/raw/main/images/Metadata%20Profile%20as%20mounted%20drive.png)


# Getting Started

## Setup

Begin by downloading the latest release.  Extract the contents of the archive into your Nuix scripts directory.  In Windows the script directory is likely going to be either of the following:

- `%appdata%\Nuix\Scripts` - User level script directory
- `%programdata%\Nuix\Scripts` - System level script directory

## Usage

### Prepare your metadata profile

The metadata is evaluated for every selected item, appended together with a "/" character 
Exif Make               Exif Model    Exif Date   Exif Time
OLYMPUS IMAGING CORP  	FE20/X15/C25	2009_03_26	15_52_25_000

Will become a path of 
OLYMPUS IMAGING CORP/FE20/X15/C25/2009_03_26/15_52_25_000 + extension

This metadata itself could have a / which will be treated as a file path element too, so a metadata profile of 'Path' would work just the same.
Some characters will be stripped if they are not compatible with webDav/windows, also directory names are stripped of additional white spaces as this can break some legacy webDav clients.

Careful: Metadata profiles which required 'selected' objects like 'selected item set' or 'selected production set ids' will return empty values. Scripts are unaware of your selected UI elements. If you need to use these it can be done by only having one production set or one item set and using the generic 'production set ids' rather than the selected versions.

### Filter your items

For the example of Exif navigation a selection of :

```kind:image AND properties:( "Exif IFD0: Make" OR "Exif IFD0: Model" )```

### Ensure you have access to the binary source

To do this attempt to do a 'save as...' through the workstation GUI. If there are errors here it would be a good idea to make your source available.

### Scripts -> Run Case Mount

This will prompt for two components:
Metadata Profile <-- Use your prepared one from earlier
IP Address <-- most of the time the server will default to 127.0.0.1 for private access, however you can change it for a network address and allow others access to your case.

### Wait

A cache will be built (progress dialog) which after a short while will finish and a drive letter will be shown to the user.
Drive letter is chosen from N: onwards.

### Enjoy navigating!

When you are finished, disconnect the drive in windows. The script checks every few seconds for the drives presence and when it is no longer used the webDav server will be stopped.

As a failsafe when the case goes into a processing/reloading/closing states the server will also be stopped.

### Extra
The port is usually going to be port 80, if unavailable will choose the next port.
Similarly with Drive letter, the default is N: if unavailable the next letter will be chosen

# License

```
Copyright 2021 Nuix

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
