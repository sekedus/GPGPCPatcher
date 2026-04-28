<#
.SYNOPSIS
    Patch Service.exe/ServiceLib.dll using Mono.Cecil loaded in PowerShell
.DESCRIPTION
    Replicates hpesuperpower.exe functionality:
    1. Downloads Mono.Cecil NuGet package
    2. Loads Cecil assemblies into PowerShell
    3. Patches Service.exe/ServiceLib.dll to:
       - Remove foreground app limit (production version only)
       - Enable Houdini ARM translation layer
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Patch-Service.ps1
.EXAMPLE
    .\_Patch-Service.ps1 -Dev
.EXAMPLE
    .\_Patch-Service.ps1 -Dev -WorkDir "..\dev-26.3.725.2"
.NOTES
    Requires: PowerShell 5.1+ (Admin) and internet connection for Mono.Cecil download (first run only)
    Reference: https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/UnlockCommand.cs#L60
#>

param(
    [switch]$Dev,
    [string]$WorkDir
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\HelperModule.psm1" -Force

$installDir = Get-InstallDir -Dev:$Dev
$versionName = if ($Dev) { "Dev" } else { "Prod" }
$patcherDir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrEmpty($WorkDir)) {
    # Default to patcher directory if not set
    $WorkDir = $patcherDir
} elseif (-not [System.IO.Path]::IsPathRooted($WorkDir)) {
    $WorkDir = Join-Path $patcherDir $WorkDir
    $WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Service.exe/ServiceLib.dll Patcher" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# =======================================================
# Helper Functions
# =======================================================

function Get-MonoCecil {
    param([string]$TargetDir)

    $cecilVersion = "0.11.6"
    $nugetUrl = "https://www.nuget.org/api/v2/package/Mono.Cecil/$cecilVersion"
    $cecilDir = Join-Path $TargetDir "Mono.Cecil"
    $cecilDll = Join-Path $cecilDir "lib\net40\Mono.Cecil.dll"

    if (Test-Path $cecilDll) {
        Write-Host "Mono.Cecil already available" -ForegroundColor Yellow
        Write-Host ""
        return $cecilDir
    }

    Write-Host "Downloading Mono.Cecil $cecilVersion..." -ForegroundColor Green

    $nupkgPath = Join-Path $TargetDir "Mono.Cecil.$cecilVersion.nupkg"

    try {
        Invoke-WebRequest -Uri $nugetUrl -OutFile $nupkgPath -UseBasicParsing
        Write-Host "  Downloaded NuGet package" -ForegroundColor Gray
    } catch {
        Write-Host "ERROR: Failed to download Mono.Cecil" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Yellow
        throw
    }
    Write-Host ""

    # Extract (NuGet package is a ZIP)
    Write-Host "Extracting Mono.Cecil..." -ForegroundColor Green

    if (Test-Path $cecilDir) {
        Remove-Item $cecilDir -Recurse -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgPath, $cecilDir)

    Remove-Item $nupkgPath -Force

    if (-not (Test-Path $cecilDll)) {
        throw "Mono.Cecil.dll not found after extraction"
    }

    Write-Host "  Mono.Cecil extracted" -ForegroundColor Gray
    Write-Host ""

    return $cecilDir
}

function Load-MonoCecil {
    param([string]$CecilDir)

    Write-Host "Loading Mono.Cecil assemblies..." -ForegroundColor Gray

    $libDir = Join-Path $CecilDir "lib\net40"

    $assemblies = @(
        "Mono.Cecil.dll",
        "Mono.Cecil.Pdb.dll",
        "Mono.Cecil.Mdb.dll",
        "Mono.Cecil.Rocks.dll"
    )

    foreach ($asm in $assemblies) {
        $asmPath = Join-Path $libDir $asm
        if (Test-Path $asmPath) {
            try {
                [System.Reflection.Assembly]::LoadFrom($asmPath) | Out-Null
                Write-Host "  Loaded: $asm" -ForegroundColor Gray
            } catch {
                Write-Host "  Failed to load: $asm" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
}

function Remove-ForegroundLimit {
    param([Mono.Cecil.ModuleDefinition]$Module)

    Write-Host "Removing foreground app limit..." -ForegroundColor Green

    try {
        $appSessionScope = $Module.GetType("Google.Hpe.Service.AppSession.AppSessionScope")

        if (-not $appSessionScope) {
            Write-Host "  AppSessionScope type not found - may be unsupported version" -ForegroundColor Yellow
            return $false
        }

        $method = $appSessionScope.Methods | Where-Object { $_.Name -eq "HandleEmulatorSurfaceStateUpdate" }

        if (-not $method) {
            Write-Host "  HandleEmulatorSurfaceStateUpdate method not found" -ForegroundColor Yellow
            return $false
        }

        $instructions = $method.Body.Instructions

        # Find instruction that references _transientForegroundPackages
        $beginIdx = -1
        for ($i = 0; $i -lt $instructions.Count; $i++) {
            $instr = $instructions[$i]
            if ($instr.Operand -is [Mono.Cecil.FieldDefinition]) {
                if ($instr.Operand.Name -eq "_transientForegroundPackages") {
                    $beginIdx = $i
                    break
                }
            }
        }

        if ($beginIdx -eq -1) {
            Write-Host "  _transientForegroundPackages field reference not found" -ForegroundColor Yellow
            Write-Host "    Foreground limit may already be removed or structure changed" -ForegroundColor Gray
            return $false
        }

        Write-Host "  Found patch location at instruction index: $beginIdx" -ForegroundColor Gray

        # Remove instructions until Leave_S
        $removed = 0
        while ($beginIdx -lt $instructions.Count) {
            $instr = $instructions[$beginIdx]
            if ($instr.OpCode.Name -eq "leave.s") {
                break
            }
            $instructions.RemoveAt($beginIdx)
            $removed++
        }

        Write-Host "  Removed $removed instructions" -ForegroundColor Gray
        return $true

    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
        return $false
    }
}

function Enable-Houdini {
    param(
        [Mono.Cecil.ModuleDefinition]$Module,
        [bool]$IsDev
    )

    Write-Host "Enabling Houdini ARM translation layer..." -ForegroundColor Green

    try {
        $className = if ($IsDev) {
            "Google.Hpe.Service.KiwiEmulator.EmulatorFeaturePolicyDev"
        } else {
            "Google.Hpe.Service.KiwiEmulator.EmulatorFeaturePolicyProd"
        }

        Write-Host "  Target class: $className" -ForegroundColor Gray

        $clazz = $Module.GetType($className)

        if (-not $clazz) {
            Write-Host "  Feature policy class not found" -ForegroundColor Yellow
            return $false
        }

        # New-style: IsHoudiniEnabled is a method (not a property/field)
        $houdiniMethod = $clazz.Methods | Where-Object {
            $_.Name -eq "IsHoudiniEnabled" -and
            $_.ReturnType.MetadataType -eq [Mono.Cecil.MetadataType]::Boolean
        } | Select-Object -First 1

        if ($houdiniMethod) {
            Write-Host "  Found IsHoudiniEnabled method (new-style) - rewriting body to return true" -ForegroundColor Gray

            $proc = $houdiniMethod.Body.GetILProcessor()
            $houdiniMethod.Body.Instructions.Clear()
            $houdiniMethod.Body.ExceptionHandlers.Clear()

            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1) # Load constant 1 (true)
            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Ret)      # Return

            Write-Host "  Patched IsHoudiniEnabled method" -ForegroundColor Gray
            return $true
        }

        # Old-style: IsHoudiniEnabled is an auto-property backed by a field
        $field = $clazz.Fields | Where-Object { $_.Name -like "*IsHoudiniEnabled*" } | Select-Object -First 1

        if (-not $field) {
            Write-Host "  IsHoudiniEnabled field not found" -ForegroundColor Yellow
            Write-Host "    Houdini may already be enabled or structure changed" -ForegroundColor Gray
            return $false
        }

        Write-Host "  Found backing field: $($field.Name) (old-style) - patching constructors" -ForegroundColor Gray

        # Patch all constructors to set field to true
        $ctors = @($clazz.Methods | Where-Object { $_.IsConstructor -and -not $_.IsStatic })

        if ($ctors.Count -eq 0) {
            Write-Host "  No instance constructors found" -ForegroundColor Yellow
            return $false
        }

        foreach ($ctor in $ctors) {
            $proc = $ctor.Body.GetILProcessor()
            $instructions = $ctor.Body.Instructions
            $retInstr = $instructions[$instructions.Count - 1]

            # Insert before return:
            # ldarg.0 (load 'this')
            # ldc.i4.1 (load constant 1 = true)
            # stfld IsHoudiniEnabled (store to field)

            $ldarg0 = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
            $ldc1 = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)
            $stfld = $proc.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $field)

            $proc.InsertBefore($retInstr, $ldarg0)
            $proc.InsertBefore($retInstr, $ldc1)
            $proc.InsertBefore($retInstr, $stfld)
        }

        Write-Host "  Patched $($ctors.Count) constructor(s)" -ForegroundColor Gray
        return $true

    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
        return $false
    }
}

function Add-LauncherPackageNames {
    param([Mono.Cecil.ModuleDefinition]$Module)

    Write-Host "Patching PackageIsLauncher to include additional launchers..." -ForegroundColor Green

    try {
        $appSessionScope = $Module.GetType("Google.Hpe.Service.AppSession.AppSessionScope")
        if (-not $appSessionScope) {
            Write-Host "  AppSessionScope type not found - may be unsupported version" -ForegroundColor Yellow
            return $false
        }

        $method = $appSessionScope.Methods | Where-Object {
            $_.Name -eq "PackageIsLauncher" -and
            $_.Parameters.Count -eq 1 -and
            $_.Parameters[0].ParameterType.MetadataType -eq [Mono.Cecil.MetadataType]::String -and
            $_.ReturnType.MetadataType -eq [Mono.Cecil.MetadataType]::Boolean
        } | Select-Object -First 1

        if (-not $method) {
            Write-Host "  PackageIsLauncher method not found" -ForegroundColor Yellow
            return $false
        }

        $proc = $method.Body.GetILProcessor()
        $method.Body.Instructions.Clear()
        $method.Body.ExceptionHandlers.Clear()

        $equalityMethod = [System.String].GetMethod("op_Equality", [Type[]]@([string], [string]))
        if (-not $equalityMethod) {
            throw "Unable to resolve System.String.op_Equality"
        }

        $eqRef = $Module.ImportReference($equalityMethod)

        $trueInstr = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)
        $falseInstr = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
        $retFalse = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ret)
        $retTrue = $proc.Create([Mono.Cecil.Cil.OpCodes]::Ret)

        $launcherPackages = @(
            "com.google.android.apps.play.battlestar.empty_launcher",
            "com.android.launcher3",
            "app.lawnchair",
            "app.lawnchair.play"
        )

        foreach ($package in $launcherPackages) {
            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Ldstr, $package)
            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Call, $eqRef)
            $proc.Emit([Mono.Cecil.Cil.OpCodes]::Brtrue_S, $trueInstr)
        }

        $proc.Append($falseInstr)
        $proc.Append($retFalse)
        $proc.Append($trueInstr)
        $proc.Append($retTrue)

        if ($method.Body.GetType().GetMethod("OptimizeMacros")) {
            $method.Body.OptimizeMacros()
        }

        Write-Host "  Patched PackageIsLauncher" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
        return $false
    }
}

# Check if GPGPC is running
Test-Running -Dev:$Dev -InstallDir $installDir

# Auto-determine service path
$basePath = "$installDir\service"
$serviceLib = Join-Path $basePath "ServiceLib.dll"
$serviceExe = Join-Path $basePath "Service.exe"
if (Test-Path $serviceLib) {
    $servicePath = $serviceLib
} elseif (Test-Path $serviceExe) {
    $servicePath = $serviceExe
} else {
    Write-Host "ERROR: Neither ServiceLib.dll nor Service.exe found!" -ForegroundColor Red
    Write-Host "  Expected location: $basePath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
$targetName = Split-Path -Leaf $ServicePath

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Version: $versionName" -ForegroundColor Gray
Write-Host "  Target: $targetName" -ForegroundColor Gray
Write-Host "  Path: $servicePath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

# Create backup directory if it doesn't exist
$backupDir = Join-Path $WorkDir "backup"
New-Directory -Path $backupDir

# Create backup file
$backupPath = Join-Path $backupDir $targetName
if (-not (Test-Path $backupPath)) {
    Write-Host "Creating backup..." -ForegroundColor Green
    Copy-Item $servicePath $backupPath
    Write-Host "  Backup: $backupPath" -ForegroundColor Gray
} else {
    Write-Host "Backup already exists: $backupPath" -ForegroundColor Yellow
}
Write-Host ""

# Download/load Mono.Cecil
$resourceDir = Join-Path $patcherDir 'resources'
New-Directory -Path $resourceDir
$cecilDir = Get-MonoCecil -TargetDir $resourceDir
Load-MonoCecil -CecilDir $cecilDir

# =======================================================
# Load and Patch Assembly
# =======================================================

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Loading Assembly" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Read assembly
    Write-Host "Reading assembly: $targetName" -ForegroundColor Green

    $readerParams = New-Object Mono.Cecil.ReaderParameters
    $resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
    $resolver.AddSearchDirectory((Split-Path $servicePath -Parent))
    $readerParams.AssemblyResolver = $resolver

    $assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($backupPath, $readerParams)
    $module = $assembly.MainModule

    Write-Host "  Assembly loaded" -ForegroundColor Gray
    Write-Host "  Version: $($assembly.Name.Version)" -ForegroundColor Gray
    Write-Host "  Full name: $($assembly.Name.FullName)" -ForegroundColor Gray
    Write-Host ""

    # =======================================================
    # Patch 1: Remove Foreground Limit (Production version only)
    # =======================================================

    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "  PATCH 1: Remove Foreground App Limit" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not $Dev) {
        $result1 = Remove-ForegroundLimit -Module $module
        Write-Host ""

        if ($result1) {
            Write-Host "Foreground limit removed" -ForegroundColor Green
        } else {
            Write-Host "Foreground limit patch skipped" -ForegroundColor Yellow
        }
        Write-Host ""
    } else {
        Write-Host "Skipping foreground limit removal (Developer version)" -ForegroundColor Gray
        Write-Host ""
    }

    # =======================================================
    # Patch 2: Enable Houdini
    # =======================================================

    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "  PATCH 2: Enable Houdini ARM Translation" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    $result2 = Enable-Houdini -Module $module -IsDev $Dev
    Write-Host ""

    if ($result2) {
        Write-Host "Houdini ARM translation enabled" -ForegroundColor Green
    } else {
        Write-Host "Houdini patch skipped" -ForegroundColor Yellow
    }
    Write-Host ""

    # =======================================================
    # Patch 3: Add extra launcher package names
    # =======================================================

    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "  PATCH 3: Add extra launcher package names" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    $result3 = Add-LauncherPackageNames -Module $module
    Write-Host ""

    if ($result3) {
        Write-Host "Launcher package names updated" -ForegroundColor Green
    } else {
        Write-Host "Launcher package patch skipped" -ForegroundColor Yellow
    }
    Write-Host ""

    # =======================================================
    # Save Patched Assembly
    # =======================================================

    if ($result1 -or $result2 -or $result3) {
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host "  Saving Patched Assembly" -ForegroundColor Cyan
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "Writing patched assembly..." -ForegroundColor Green

        $writerParams = New-Object Mono.Cecil.WriterParameters
        $assembly.Write($servicePath, $writerParams)

        Write-Host "  Assembly saved" -ForegroundColor Gray
        Write-Host ""

        Write-Host "====================================================" -ForegroundColor Green
        Write-Host "  SUCCESS: $targetName patched" -ForegroundColor Green
        Write-Host "====================================================" -ForegroundColor Green
        Write-Host ""

        Write-Host "What was done:" -ForegroundColor Cyan
        if ($result1) {
            Write-Host "  Foreground app limit removed" -ForegroundColor White
            Write-Host "    All apps can run in background" -ForegroundColor Gray
        }
        if ($result2) {
            Write-Host "  Houdini ARM translation enabled" -ForegroundColor White
            Write-Host "    ARM apps can now run" -ForegroundColor Gray
        }
        if ($result3) {
            Write-Host "  Launcher package names updated" -ForegroundColor White
            Write-Host "    app.lawnchair and app.lawnchair.play added" -ForegroundColor Gray
        }
        Write-Host ""

        Write-Host "Backup:" -ForegroundColor Cyan
        Write-Host "  Original file saved to:" -ForegroundColor White
        Write-Host "    $backupPath" -ForegroundColor Gray
        Write-Host ""

    } else {
        Write-Host "====================================================" -ForegroundColor Yellow
        Write-Host "  NO PATCHES APPLIED" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "Possible reasons:" -ForegroundColor Yellow
        Write-Host "  - Assembly already patched" -ForegroundColor Gray
        Write-Host "  - Unsupported version" -ForegroundColor Gray
        Write-Host "  - Structure changed in update" -ForegroundColor Gray
        Write-Host ""

        Write-Host "Original file unchanged." -ForegroundColor Gray
        Write-Host ""
    }

    # Dispose assembly
    $assembly.Dispose()

} catch {
    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Red
    Write-Host "  PATCHING FAILED" -ForegroundColor Red
    Write-Host "====================================================" -ForegroundColor Red
    Write-Host ""

    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host "  $($_.Exception.Message)" -ForegroundColor White
    Write-Host ""

    if ($_.Exception.InnerException) {
        Write-Host "Inner exception:" -ForegroundColor Yellow
        Write-Host "  $($_.Exception.InnerException.Message)" -ForegroundColor White
        Write-Host ""
    }

    Write-Host "Stack trace:" -ForegroundColor Gray
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "If backup exists, restore with:" -ForegroundColor Cyan
    Write-Host "  Copy-Item '$backupPath' '$servicePath' -Force" -ForegroundColor White
    Write-Host ""

    exit 1
}
