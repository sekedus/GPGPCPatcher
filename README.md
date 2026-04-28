<div align="left">
<picture><img align="left" width="38" alt="GPGPC Patcher" src="https://github.com/user-attachments/assets/25db36a4-cd98-417c-8277-88d27159eae4"></picture>
<h1>GPGPC Patcher</h1>
</div>

<picture>![Badge Repo Size]</picture>
[![Badge License]](./LICENSE)
[![Badge Downloads]](#download)

<picture>![Badge Magisk]</picture>
<picture>![Badge GPGPC Prod]</picture>
<picture>![Badge GPGPC Dev]</picture>

<br/>

A patcher for Google Play Games on PC (GPGPC), supports the Production (retail/regular) and Developer Emulator versions.  

Provides utilities to extract and flash partitions, root with Magisk, modify super.img, and disable verified boot checks.

Also includes tools to patch service binaries and configuration, patch bios.rom, enable ADB, and run supporting shell helpers under WSL2.

Intended for <ins>**advanced users**</ins> and <ins>**developers**</ins> who want to customize, research, or automate modifications to the GPGPC environment.

<br/>

> [!NOTE]  
> The full name "Google Play Games on PC" is too long to repeat frequently.  
> This guide and patcher use the abbreviation `GPGPC` for "Google Play Games on PC".  
> For brevity:
> - `Prod` or `GPGPCP` refers to Production (retail/regular) version
> - `Dev` or `GPGPCDE` refers to Developer Emulator version.

<br/>

> [!WARNING]  
> This repository contains only the script code.  
> **To run the patch, always download the [latest release](#download).**  
> The release contains the patcher script and all required files.

<br/>

## Table of Contents

- [Prerequisites](#prerequisites)
- [Download](#download)
- [Preparation](#preparation)
- [Patch](#patch)
  - [Auto (recommended)](#auto-recommended)
  - [Manual](#manual)
- [Restore](#restore)
- [Update](#update)
- [Troubleshooting](#troubleshooting)
- [Example Directory Structure](#example-directory-structure)
- [Credits](#credits)
- [Disclaimer](#disclaimer)
- [License](#license)

<br/>

## [Screenshots](./screenshots/README.md)

<br/>

## Prerequisites

- PowerShell 5.1+ as Administrator
- [WSL2 (Windows Subsystem for Linux)](https://aka.ms/wslinstall) with:
  - A Linux distribution (e.g., Ubuntu)
  - [sudo (Super User Do)](https://aka.ms/wslusers)
  - `bc`
  - `unzip`
  - `android-sdk-libsparse-utils` (simg2img and img2simg)
  - `e2fsprogs` (e2fsck and resize2fs)
- Google Play Games on PC (GPGPC)
  - [Production (Prod)](https://g.co/googleplaygames)
  - [Developer Emulator (Dev)](https://developer.android.com/games/playgames/emulator)
- Free disk space: **20 GB** (for backups, extracted images, and patched files)

<br/>

## Preparation

1. Install WSL2 and a Linux distribution (e.g., Ubuntu).
2. Set up a user account in WSL2 and make sure you can run `sudo` commands.
3. Install required packages in WSL2:

   ```bash
   sudo apt update
   sudo apt install bc unzip android-sdk-libsparse-utils e2fsprogs
   ```
4. Install GPGPC Prod and/or Dev.  

   ⚠️ For GPGPC Prod, both `Prod` and `Dev` versions need to be **installed**, because files from both versions are required for patching.
5. Launch GPGPC:

   - **Prod**: Open Google Play Games > **sign in** > Open [Advanced settings](./TROUBLESHOOTING.md#open-advanced-settings-in-google-play-games-on-pc-prod) > then [close it completely][exit-gpgpc].
   - **Dev**: Open Developer Emulator > **sign in** > Allow `USB debugging` > then [close it completely][exit-gpgpc].
6. Make sure GPGPC `Prod` or `Dev` is **not running** before starting patch.

<br/>

## Download

1. [Download the latest release](https://github.com/sekedus/GPGPCPatcher/releases/latest).
2. Unzip the downloaded archive to a folder (e.g., `D:\GPGPC-patcher`).
3. Open PowerShell [as Administrator in patcher folder](https://superuser.com/a/1309680).

<br/>

## Patch

Before proceeding, choose one of the two patching methods:
- **Auto (recommended)**: Runs the full patch sequence with minimal input. This is suitable for most users.
- **Manual**: Shows each command step-by-step so advanced users can review or run steps selectively.

Pick one option below and follow its instructions. **Do not** mix patching methods.

<br/>

### Auto (recommended)

> [!IMPORTANT]  
> You will need to manually enter your **sudo password** when prompted during the automatic patch process  
> or [temporarily disable sudo password prompt](./TROUBLESHOOTING.md#temporarily-disable-sudo-password-prompt-wsl2) in WSL2.

Run patch automatically:

```powershell
.\GPGPC-patcher.ps1 -MagiskApk "resources\Magisk_30.7.apk"

# For dev version
.\GPGPC-patcher.ps1 -Dev -MagiskApk "resources\Magisk_30.7.apk"
```

<br/>

### Manual

> [!IMPORTANT]  
> Before performing manual patch steps, you must obtain the **working directory path**.  
> Run `.\Get-WorkDir.ps1` and use the printed `__WORK_DIR__` value in the subsequent manual commands.

<details>
<summary>(<strong>click to expand</strong>) 👈</summary>

#### Get Working Directory

```powershell
.\Get-WorkDir.ps1
```

#### 1. Patch Service.exe/ServiceLib.dll

```powershell
# Patch .dll first; if not found, patch .exe
.\scripts\_Patch-Service.ps1 -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Patch-Service.ps1 -Dev -WorkDir __WORK_DIR__
```

#### 2. Patch Service.exe.config

```powershell
.\scripts\_Patch-ServiceConfig.ps1 -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Patch-ServiceConfig.ps1 -Dev -WorkDir __WORK_DIR__
```

#### 3. Extract boot_a.img from aggregate.img

```powershell
.\scripts\_Extract-Partition.ps1 -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Extract-Partition.ps1 -Dev -WorkDir __WORK_DIR__
```

#### 4. Patch boot with Magisk + Superpower

```powershell
.\scripts\_Patch-BootWithMagisk.ps1 `
    -MagiskApk "resources\Magisk_30.7.apk" `
    -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Patch-BootWithMagisk.ps1 `
    -Dev `
    -MagiskApk "resources\Magisk_30.7.apk" `
    -WorkDir __WORK_DIR__
```

#### 5. Flash boot_a-patched.img to aggregate.img

```powershell
.\scripts\_Flash-Partition.ps1 -Y -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Flash-Partition.ps1 -Dev -Y -WorkDir __WORK_DIR__
```

#### 6. Extract super.img from aggregate.img

```powershell
.\scripts\_Extract-Partition.ps1 -PartitionName "super" -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Extract-Partition.ps1 -Dev -PartitionName "super" -WorkDir __WORK_DIR__
```

#### 7. Patch super.img

> [!IMPORTANT]  
> You will need to manually enter your **sudo password** when prompted.

```powershell
.\scripts\_Patch-Super.ps1 -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Patch-Super.ps1 -Dev -WorkDir __WORK_DIR__
```

**Patch includes:**

- Remove `init.user.rc` from `product_a.img`
- Add APK as system app to `system_a.img` (Prod)
- Add `adbproxy` to `vendor_a.img` (Prod)

#### 8. Flash super-patched.img to aggregate.img

```powershell
.\scripts\_Flash-Partition.ps1 -Y -PartitionName "super" -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Flash-Partition.ps1 -Dev -Y -PartitionName "super" -WorkDir __WORK_DIR__
```

#### 9. Extract vbmeta from aggregate.img

```powershell
.\scripts\_Extract-Partition.ps1 -PartitionName "vbmeta_a" -WorkDir __WORK_DIR__
.\scripts\_Extract-Partition.ps1 -PartitionName "vbmeta_system_a" -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Extract-Partition.ps1 -Dev -PartitionName "vbmeta_a" -WorkDir __WORK_DIR__
.\scripts\_Extract-Partition.ps1 -Dev -PartitionName "vbmeta_system_a" -WorkDir __WORK_DIR__
```

#### 10. Disable AVB (Android Verified Boot) on vbmeta

```powershell
.\scripts\_Patch-Vbmeta.ps1 -WorkDir __WORK_DIR__
.\scripts\_Patch-Vbmeta.ps1 -VbmetaName "vbmeta_system_a" -WorkDir __WORK_DIR__
```

#### 11. Flash vbmeta to aggregate.img

```powershell
.\scripts\_Flash-Partition.ps1 -Y -PartitionName "vbmeta_a" -WorkDir __WORK_DIR__
.\scripts\_Flash-Partition.ps1 -Y -PartitionName "vbmeta_system_a" -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Flash-Partition.ps1 -Dev -Y -PartitionName "vbmeta_a" -WorkDir __WORK_DIR__
.\scripts\_Flash-Partition.ps1 -Dev -Y -PartitionName "vbmeta_system_a" -WorkDir __WORK_DIR__
```

#### 12. Patch bios.rom

```powershell
.\scripts\_Patch-Bios.ps1 -WorkDir __WORK_DIR__

# For dev version
.\scripts\_Patch-Bios.ps1 -Dev -WorkDir __WORK_DIR__
```

#### 13. Enable ADB (Prod version)

⚠️ The GPGPC **Dev** version **must be installed** for ADB to work in the **Prod** version.

```powershell
.\scripts\_Enable-ADB.ps1 -Force -WorkDir __WORK_DIR__
```

</details>

<br/>

## Restore

Restore the original files from `__WORK_DIR__\backup\` to undo the patch and return to an unmodified state.  
The `backup` folder is created automatically by the patcher when it modifies files.  
It contains original binaries, configuration files, and other files replaced by the patch.  

Before restoring:
- [Completely exit][exit-gpgpc] the Google Play Games on PC (GPGPC) Prod or Dev version if it is running.
- Verify the `backup` folder exists in the working directory and contains the necessary files to restore.

Run the restore script:
```powershell
.\GPGPC-patcher.ps1 -Restore

# For dev version
.\GPGPC-patcher.ps1 -Dev -Restore
```

<br/>

## Update

Every time you update Google Play Games on PC (GPGPC), you must reapply the patch.

Updating the application replaces the patched binaries. This process removes root access, reverts modifications to `super`/`boot`/`vbmeta`, and clears any changes to service binaries and configuration.

After each update, repeat the patching process (automatic or manual) to restore the modifications.

<br/>

## [Troubleshooting](./TROUBLESHOOTING.md)

<br/>

## Example Directory Structure

> [!NOTE]  
> In the examples below, `dev-26.4.112.1` and `prod-26.4.112.1` are **&#95;&#95;WORK_DIR&#95;&#95;** values (the working directory output by `Get-WorkDir.ps1`).

<details>
<summary>(<strong>click to expand</strong>) 👈</summary>

<br/>

```
.
|-- dev-26.4.112.1
|   |-- backup
|   |   |-- Service.exe.config
|   |   |-- ServiceLib.dll
|   |   |-- aggregate.img
|   |   `-- bios.rom
|   |-- extracted
|   |   |-- super_unpacked
|   |   |   |-- product_a.img
|   |   |   |-- product_b.img
|   |   |   |-- system_a.img
|   |   |   |-- system_b.img
|   |   |   |-- vendor_a.img
|   |   |   `-- vendor_b.img
|   |   |-- _sha256-boot_a.txt
|   |   |-- _sha256-super.txt
|   |   |-- _sha256-vbmeta_a.txt
|   |   |-- _sha256-vbmeta_system_a.txt
|   |   |-- boot_a.img
|   |   |-- super.img
|   |   |-- vbmeta_a.img
|   |   `-- vbmeta_system_a.img
|   `-- patched
|       |-- boot_a-patched.img
|       |-- vbmeta_a-patched.img
|       `-- vbmeta_system_a-patched.img
|-- prod-26.4.112.1
|   |-- backup
|   |   |-- adb
|   |   |   |-- CrashReporting.dll
|   |   |   |-- GuiLibExport.dll
|   |   |   |-- cperfetto.dll
|   |   |   |-- crosvm.exe
|   |   |   |-- gfxstream_backend.dll
|   |   |   |-- libglib-2.0-0.dll
|   |   |   |-- libiconv-2.dll
|   |   |   |-- libintl-8.dll
|   |   |   |-- libpcre2-8-0.dll
|   |   |   |-- libsecure_env.dll
|   |   |   |-- libsecurity.dll
|   |   |   |-- libslirp-0.dll
|   |   |   |-- r8Brain.dll
|   |   |   `-- recorder_delegate_lib.dll
|   |   |-- Service.exe.config
|   |   |-- ServiceLib.dll
|   |   |-- aggregate.img
|   |   `-- bios.rom
|   |-- extracted
|   |   |-- super_unpacked
|   |   |   |-- new
|   |   |   |   |-- product_a_new.img
|   |   |   |   |-- system_a_new.img
|   |   |   |   `-- vendor_a_new.img
|   |   |   |-- product_a.img
|   |   |   |-- product_b.img
|   |   |   |-- system_a.img
|   |   |   |-- system_b.img
|   |   |   |-- vendor_a.img
|   |   |   `-- vendor_b.img
|   |   |-- _sha256-boot_a.txt
|   |   |-- _sha256-super.txt
|   |   |-- _sha256-vbmeta_a.txt
|   |   |-- _sha256-vbmeta_system_a.txt
|   |   |-- boot_a.img
|   |   |-- super.img
|   |   |-- vbmeta_a.img
|   |   `-- vbmeta_system_a.img
|   `-- patched
|       |-- boot_a-patched.img
|       |-- super-patched.img
|       |-- vbmeta_a-patched.img
|       `-- vbmeta_system_a-patched.img
|-- resources
|   |-- bin
|   |   |-- adbproxy
|   |   |-- lpdump
|   |   |-- lpmake
|   |   `-- lpunpack
|   |-- Mono.Cecil
|   |   `-- lib
|   |       `-- net40
|   |           |-- Mono.Cecil.Mdb.dll
|   |           |-- Mono.Cecil.Pdb.dll
|   |           |-- Mono.Cecil.Rocks.dll
|   |           |-- Mono.Cecil.dll
|   |-- Launcher3QuickStep.zip
|   |-- Magisk_30.7.apk
|   |-- superpower-dev.apk
|   `-- superpower-prod.apk
|-- scripts
|   |-- _Extract-Partition.ps1
|   |-- _Flash-Partition.ps1
|   |-- _Patch-Bios.ps1
|   |-- _Patch-BootWithMagisk.ps1
|   |-- _Patch-Service.ps1
|   |-- _Patch-ServiceConfig.ps1
|   |-- _Patch-Super.ps1
|   |-- _Patch-Vbmeta.ps1
|   |-- magisk_patch-boot.sh
|   |-- super_patch-product.sh
|   |-- super_patch-system.sh
|   |-- super_patch-vendor.sh
|   |-- super_repack.sh
|   `-- super_unpack.sh
|-- GPGPC-patcher.ps1
|-- Get-WorkDir.ps1
|-- HelperModule.psm1
|-- LICENSE
```

</details>

<br/>

## Credits

- [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk/releases?q=prerelease%3Afalse)
- [chsbuffer/hpesuperpower](https://github.com/chsbuffer/hpesuperpower?tab=readme-ov-file)
- XDA Forums
  - [t-4486817#post-90018526](https://xdaforums.com/t/4486817/post-90018526)
  - [t-4486817#post-90052467](https://xdaforums.com/t/4486817/post-90052467)
  - [t-4196625](https://xdaforums.com/t/4196625/)
- [jbevain/cecil](https://github.com/jbevain/cecil?tab=readme-ov-file)
- [itsNileshHere/android-lptools](https://github.com/itsNileshHere/android-lptools?tab=readme-ov-file)
- [Hovatek Forum &#8211; 49389](https://www.hovatek.com/forum/thread-49389.html)
- [Android Stack Exchange &#8211; 161288](https://android.stackexchange.com/a/161288)
- [libxzr/vbmeta-disable-verification](https://github.com/libxzr/vbmeta-disable-verification?tab=readme-ov-file)
- [Explaining Android &#8211; 3pxRLjOQFnc](https://youtu.be/3pxRLjOQFnc)
- [GPGPC Logo](https://commons.wikimedia.org/wiki/File:Google_Play_Games_logo_(2023).svg)

<br/>

## Disclaimer

This project is provided for **educational and research purposes only**. It is not affiliated with or endorsed by Google. **USE AT YOUR OWN RISK!**

The authors and contributors are **not responsible for any damage, data loss, legal issues, or other consequences.**

<br/>

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE](./LICENSE) file for more details.


<!-- Url -->

[exit-gpgpc]: ./TROUBLESHOOTING.md#exit-google-play-games-on-pc

<!-- Badges -->

[Badge Repo Size]: https://img.shields.io/github/repo-size/sekedus/GPGPCPatcher?label=Size
[Badge License]: https://img.shields.io/github/license/sekedus/GPGPCPatcher?label=License
[Badge Downloads]: https://img.shields.io/github/downloads/sekedus/GPGPCPatcher/total?label=Downloads
[Badge Magisk]: https://img.shields.io/badge/Magisk-v30.7-00AF9C.svg?logo=Magisk
[Badge GPGPC Prod]: https://img.shields.io/badge/GPGPC%20(Prod)-26.4.112.1-1A8039.svg?logo=data:image/svg%2bxml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSIgdmlld0JveD0iMCAwIDQ3OC42MzMgNTM0LjQ3OCI+PHBhdGggZmlsbD0iIzFBODAzOSIgZD0iTTAgNDc1LjIyVjU5LjIyOUMwIDEzLjcyNyA0OS4yODUtMTQuNzc2IDg4Ljc3NCA4LjAyN2wzNjAuMjggMjA3Ljk2OWMzOS40MzggMjIuODAzIDM5LjQzOCA3OS43MDUgMCAxMDIuNDU2TDg4Ljc3NCA1MjYuNDczQzQ5LjMzNiA1NDkuMjI0IDAgNTIwLjc3MyAwIDQ3NS4yMnoiLz48cGF0aCBmaWxsPSIjOTRGRUQ2IiBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik0yNTcuOTggMjM2LjIwOGMtNy45ODEtNDYuNDg2LTQ4LjMtODAuMjc1LTk1LjQ2LTgwLjI3NUgwdjIyMi41ODRoMTE1LjU2N2w4NC4wMDcgODQuMDA3IDg5LjAzNC01MS40MDktMzAuNjI4LTE3NC45MDd6bS0xNDIuNjItNTAuMTY2YzE1LjM0IDAgMjcuODI5IDEyLjQ5IDI3LjgyOSAyNy45ODUgMCAxNS4zNC0xMi40OSAyNy44MjktMjcuODI5IDI3LjgyOS0xNS40OTUgMC0yNy45ODUtMTIuNDktMjcuOTg1LTI3LjgyOSAwLTE1LjQ5NSAxMi40OS0yNy45ODUgMjcuOTg1LTI3Ljk4NXpNNjIuMDg1IDI5NS4xODNjLTE1LjM0IDAtMjcuODI5LTEyLjQ5LTI3LjgyOS0yNy45ODUgMC0xNS4zNCAxMi40OS0yNy44MjkgMjcuODI5LTI3LjgyOSAxNS40OTUgMCAyNy45ODUgMTIuNDkgMjcuOTg1IDI3LjgyOSAwIDE1LjQ5Ni0xMi40OSAyNy45ODUtMjcuOTg1IDI3Ljk4NXptNTMuMjc1IDUzLjEyYy0xNS40OTUgMC0yNy45ODUtMTIuMzM0LTI3Ljk4NS0yNy44MjkgMC0xNS4zNCAxMi40OS0yNy44MjkgMjcuOTg1LTI3LjgyOSAxNS4zNCAwIDI3LjgyOSAxMi40OSAyNy44MjkgMjcuODI5LjAwMSAxNS40OTUtMTIuNDg5IDI3LjgyOS0yNy44MjkgMjcuODI5em01My44NDUtNTMuMTJjLTE1LjQ5NSAwLTI3Ljk4NS0xMi40OS0yNy45ODUtMjcuOTg1IDAtMTUuMzQgMTIuNDktMjcuODI5IDI3Ljk4NS0yNy44MjkgMTUuMzQgMCAyNy44MjkgMTIuNDkgMjcuODI5IDI3LjgyOS0uMDUxIDE1LjQ5Ni0xMi41NDEgMjcuOTg1LTI3LjgyOSAyNy45ODV6IiBjbGlwLXJ1bGU9ImV2ZW5vZGQiLz48L3N2Zz4=
[Badge GPGPC Dev]: https://img.shields.io/badge/GPGPC%20(Dev)-26.4.112.1-1A8039.svg?logo=data:image/svg%2bxml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSIgdmlld0JveD0iMCAwIDQ3OC42MzMgNTM0LjQ3OCI+PHBhdGggZmlsbD0iIzFBODAzOSIgZD0iTTAgNDc1LjIyVjU5LjIyOUMwIDEzLjcyNyA0OS4yODUtMTQuNzc2IDg4Ljc3NCA4LjAyN2wzNjAuMjggMjA3Ljk2OWMzOS40MzggMjIuODAzIDM5LjQzOCA3OS43MDUgMCAxMDIuNDU2TDg4Ljc3NCA1MjYuNDczQzQ5LjMzNiA1NDkuMjI0IDAgNTIwLjc3MyAwIDQ3NS4yMnoiLz48cGF0aCBmaWxsPSIjOTRGRUQ2IiBmaWxsLXJ1bGU9ImV2ZW5vZGQiIGQ9Ik0yNTcuOTggMjM2LjIwOGMtNy45ODEtNDYuNDg2LTQ4LjMtODAuMjc1LTk1LjQ2LTgwLjI3NUgwdjIyMi41ODRoMTE1LjU2N2w4NC4wMDcgODQuMDA3IDg5LjAzNC01MS40MDktMzAuNjI4LTE3NC45MDd6bS0xNDIuNjItNTAuMTY2YzE1LjM0IDAgMjcuODI5IDEyLjQ5IDI3LjgyOSAyNy45ODUgMCAxNS4zNC0xMi40OSAyNy44MjktMjcuODI5IDI3LjgyOS0xNS40OTUgMC0yNy45ODUtMTIuNDktMjcuOTg1LTI3LjgyOSAwLTE1LjQ5NSAxMi40OS0yNy45ODUgMjcuOTg1LTI3Ljk4NXpNNjIuMDg1IDI5NS4xODNjLTE1LjM0IDAtMjcuODI5LTEyLjQ5LTI3LjgyOS0yNy45ODUgMC0xNS4zNCAxMi40OS0yNy44MjkgMjcuODI5LTI3LjgyOSAxNS40OTUgMCAyNy45ODUgMTIuNDkgMjcuOTg1IDI3LjgyOSAwIDE1LjQ5Ni0xMi40OSAyNy45ODUtMjcuOTg1IDI3Ljk4NXptNTMuMjc1IDUzLjEyYy0xNS40OTUgMC0yNy45ODUtMTIuMzM0LTI3Ljk4NS0yNy44MjkgMC0xNS4zNCAxMi40OS0yNy44MjkgMjcuOTg1LTI3LjgyOSAxNS4zNCAwIDI3LjgyOSAxMi40OSAyNy44MjkgMjcuODI5LjAwMSAxNS40OTUtMTIuNDg5IDI3LjgyOS0yNy44MjkgMjcuODI5em01My44NDUtNTMuMTJjLTE1LjQ5NSAwLTI3Ljk4NS0xMi40OS0yNy45ODUtMjcuOTg1IDAtMTUuMzQgMTIuNDktMjcuODI5IDI3Ljk4NS0yNy44MjkgMTUuMzQgMCAyNy44MjkgMTIuNDkgMjcuODI5IDI3LjgyOS0uMDUxIDE1LjQ5Ni0xMi41NDEgMjcuOTg1LTI3LjgyOSAyNy45ODV6IiBjbGlwLXJ1bGU9ImV2ZW5vZGQiLz48L3N2Zz4=
