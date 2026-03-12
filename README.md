# Portable APK to dump.cs

A simple, 100% automated tool to generate a `dump.cs` file directly from any Android game APK. No complicated setups, no command lines required!

## What it does
Takes an `.apk` file, automatically downloads the required tools (if it's your first time running it), extracts the game's code, finds the version number, and spits out a clean `[Version]_dump.cs` ready for your modding needs. It also gives `[Version]_cleaned_dump.cs` that trims down useless code that's irrelevant to modding for a more compact dump file.

## How to use it
1. Grab any Il2Cpp Android game `.apk` file.
2. Drag and drop the `.apk` file directly onto the **`1_Drop_APK_Here.bat`** file.
3. Wait a minute or two for the magic to happen.
4. Open the `output` folder to find your generated dump file!

## Features
- **Zero Install:** It downloads `Il2CppDumper` and `aapt` (for version checking) automatically!
- **Portable:** Put the folder anywhere. It runs locally and cleans up after itself.
- **Smart Extraction:** Bypasses common Android zip obfuscation methods that break normal extraction tools.

> **Note:** The first time you run this tool, it will need an internet connection to download `Il2CppDumper.exe` (~1MB) and Android Build Tools (~50MB) for version checking. After that, it works completely offline!
