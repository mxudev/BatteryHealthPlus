#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run after adding source files."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()

def obj(label, isa, **fields):
    key = uid(label)
    objects[key] = {"isa": isa, **fields}
    return key

def configs(label, settings):
    refs = []
    for name in ["Debug", "Release"]:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O",
                      DEBUG_INFORMATION_FORMAT="dwarf" if name == "Debug" else "dwarf-with-dsym")
        if name == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        refs.append(obj(label + name, "XCBuildConfiguration", name=name, buildSettings=values))
    return obj(label + "Configs", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

source_paths = sorted([*ROOT.glob("Sources/PowerCore/*.swift"), *ROOT.glob("SharedUI/*.swift"),
                       *ROOT.glob("App/*.swift"), *ROOT.glob("Widget/*.swift")])
refs = {}
for path in source_paths:
    relative = str(path.relative_to(ROOT))
    refs[relative] = obj(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
assets = obj("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="SOURCE_ROOT")
app_product = obj("appProduct", "PBXFileReference", explicitFileType="wrapper.application", path="BatteryHealth++.app", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex="0")
widget_product = obj("widgetProduct", "PBXFileReference", explicitFileType="wrapper.app-extension", path="BatteryHealthWidget.appex", sourceTree="BUILT_PRODUCTS_DIR", includeInIndex="0")
products = obj("products", "PBXGroup", name="Products", children=[app_product, widget_product], sourceTree="<group>")
main = obj("main", "PBXGroup", children=[*refs.values(), assets, products], sourceTree="<group>")

common = {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "ARCHS": "arm64",
          "SUPPORTED_PLATFORMS": "macosx", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES",
          "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": "-", "ENABLE_HARDENED_RUNTIME": "YES",
          "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0", "COMBINE_HIDPI_IMAGES": "YES",
          "SWIFT_EMIT_LOC_STRINGS": "YES", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"]}

def target(label, widget=False):
    files = []
    for path, ref in refs.items():
        if path.startswith("App/") and widget or path.startswith("Widget/") and not widget:
            continue
        files.append(obj(label + path, "PBXBuildFile", fileRef=ref))
    sources = obj(label + "Sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=files, runOnlyForDeploymentPostprocessing="0")
    frameworks = obj(label + "Frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
    resources = obj(label + "Resources", "PBXResourcesBuildPhase", buildActionMask="2147483647",
                    files=[] if widget else [obj("assetBuild", "PBXBuildFile", fileRef=assets)], runOnlyForDeploymentPostprocessing="0")
    settings = dict(common)
    settings.update(PRODUCT_NAME="BatteryHealthWidget" if widget else "BatteryHealth++",
                    PRODUCT_MODULE_NAME="BatteryHealthWidget" if widget else "BatteryHealthPlus",
                    PRODUCT_BUNDLE_IDENTIFIER="com.batteryhealthplus.mac.widget" if widget else "com.batteryhealthplus.mac",
                    INFOPLIST_FILE="Config/Widget-Info.plist" if widget else "Config/App-Info.plist",
                    CODE_SIGN_ENTITLEMENTS="Config/Widget.entitlements" if widget else "Config/App.entitlements",
                    ENABLE_APP_SANDBOX="YES" if widget else "NO")
    if widget:
        settings.update(APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES")
    else:
        settings.update(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon")
    phases = [sources, frameworks, resources]
    dependencies = []
    if not widget:
        embed_file = obj("embedWidget", "PBXBuildFile", fileRef=widget_product, settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(obj("embedPhase", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="", dstSubfolderSpec="13", files=[embed_file], name="Embed App Extensions", runOnlyForDeploymentPostprocessing="0"))
        proxy = obj("widgetProxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1", remoteGlobalIDString=uid("widget"), remoteInfo="BatteryHealthWidget")
        dependencies.append(obj("widgetDependency", "PBXTargetDependency", target=uid("widget"), targetProxy=proxy))
    return obj(label, "PBXNativeTarget", buildConfigurationList=configs(label, settings), buildPhases=phases,
               buildRules=[], dependencies=dependencies, name="BatteryHealthWidget" if widget else "BatteryHealthPlus",
               productName="BatteryHealthWidget" if widget else "BatteryHealth++",
               productReference=widget_product if widget else app_product,
               productType="com.apple.product-type.app-extension" if widget else "com.apple.product-type.application")

widget = target("widget", True)
app = target("app")
project = obj("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600"},
              buildConfigurationList=configs("project", common), compatibilityVersion="Xcode 14.0", developmentRegion="en",
              hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=main, productRefGroup=products,
              projectDirPath="", projectRoot="", targets=[app, widget])

def serialize(value, level=0):
    tab = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join(f'{tab}\t{json.dumps(k)} = {serialize(v, level+1)};\n' for k, v in value.items()) + tab + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f'{tab}\t{serialize(v, level+1)},\n' for v in value) + tab + ")"
    return json.dumps(str(value))

project_dir = ROOT / "BatteryHealthPlus.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}) + "\n")
scheme_dir = project_dir / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "BatteryHealthPlus.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="BatteryHealth++.app" BlueprintName="BatteryHealthPlus" ReferencedContainer="container:BatteryHealthPlus.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="BatteryHealth++.app" BlueprintName="BatteryHealthPlus" ReferencedContainer="container:BatteryHealthPlus.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

base_info = {"CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
             "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
             "CFBundleName": "$(PRODUCT_NAME)", "CFBundleShortVersionString": "$(MARKETING_VERSION)",
             "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)"}
app_info = dict(base_info, CFBundlePackageType="APPL", CFBundleDisplayName="BatteryHealth++", NSPrincipalClass="NSApplication",
                NSHighResolutionCapable=True, LSArchitecturePriority=["arm64"],
                CFBundleURLTypes=[{"CFBundleURLName": "Overview", "CFBundleURLSchemes": ["batteryhealthplus"]}])
widget_info = dict(base_info, CFBundlePackageType="XPC!", CFBundleDisplayName="BatteryHealth++",
                   NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})
for name, value in [("App-Info.plist", app_info), ("Widget-Info.plist", widget_info),
                    ("App.entitlements", {}),
                    ("Widget.entitlements", {"com.apple.security.app-sandbox": True,
                                             "com.apple.security.temporary-exception.iokit-user-client-class": ["AppleSMCClient"]})]:
    (ROOT / "Config" / name).write_bytes(plistlib.dumps(value))
print("Generated BatteryHealthPlus.xcodeproj")
