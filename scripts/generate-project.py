#!/usr/bin/env python3
"""Generate the small, dependency-free Xcode project from checked-in app sources."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
project = root / "Yubai.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value):
    key = ident(name); objects[key] = value; return key
def quote(value): return json.dumps(str(value), ensure_ascii=False)
source_files = sorted((root / "Sources/YubaiApp").glob("*.swift"))
refs, builds = [], []
for file in source_files:
    ref = add(str(file.relative_to(root)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
    refs.append(ref)
    builds.append(add("build:" + file.name, f'isa = PBXBuildFile; fileRef = {ref};'))
assets = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
asset_build = add("asset-build", f'isa = PBXBuildFile; fileRef = {assets};')
refs.append(assets)
privacy = add("privacy", 'isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>";')
refs.append(privacy)
privacy_build = add("privacy-build", f'isa = PBXBuildFile; fileRef = {privacy};')
source_group = add("app-group", f'isa = PBXGroup; children = ({",".join(refs)},); path = Sources/YubaiApp; sourceTree = "<group>";')
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Yubai.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = add("root-group", f'isa = PBXGroup; children = ({source_group},{products},); sourceTree = "<group>";')
package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
dependency = add("core-dependency", f'isa = XCSwiftPackageProductDependency; package = {package}; productName = YubaiCore;')
framework = add("core-link", f'isa = PBXBuildFile; productRef = {dependency};')
sources = add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = add("frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework},); runOnlyForDeploymentPostprocessing = 0;')
resources = add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({asset_build},{privacy_build},); runOnlyForDeploymentPostprocessing = 0;')
settings = '''ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    CODE_SIGN_STYLE = Automatic;
    CURRENT_PROJECT_VERSION = 1;
    GENERATE_INFOPLIST_FILE = NO;
    INFOPLIST_FILE = Sources/YubaiApp/Info.plist;
    IPHONEOS_DEPLOYMENT_TARGET = 18.0;
    MACOSX_DEPLOYMENT_TARGET = 14.0;
    MARKETING_VERSION = 1.0.0;
    PRODUCT_BUNDLE_IDENTIFIER = app.yubai.personal;
    PRODUCT_NAME = Yubai;
    SDKROOT = auto;
    SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
    SUPPORTS_MACCATALYST = NO;
    SWIFT_VERSION = 5.0;
    TARGETED_DEVICE_FAMILY = "1,2";
    LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@executable_path/../Frameworks");
'''
configs = []
for name in ["Debug", "Release"]:
    optimization = '-Onone' if name == 'Debug' else '-O'
    configs.append(add("target-config:" + name, f'isa = XCBuildConfiguration; buildSettings = {{{settings} ONLY_ACTIVE_ARCH = {"YES" if name == "Debug" else "NO"}; SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quote("DEBUG" if name == "Debug" else "")}; SWIFT_OPTIMIZATION_LEVEL = {quote(optimization)}; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; }}; name = {name};'))
config_list = add("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = Yubai; packageProductDependencies = ({dependency},); productName = Yubai; productReference = {product}; productType = "com.apple.product-type.application";')
project_configs = [add("project-config:" + name, f'isa = XCBuildConfiguration; buildSettings = {{CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; ENABLE_USER_SCRIPT_SANDBOXING = YES;}}; name = {name};') for name in ['Debug', 'Release']]
project_config_list = add("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_id = add("project", f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 2640; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 16.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base,); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
ui_ref = add("ui-test-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/YubaiUITests/AppFlowTests.swift; sourceTree = "<group>";')
ui_file_build = add("ui-test-file-build", f'isa = PBXBuildFile; fileRef = {ui_ref};')
objects[group] = objects[group].replace(f'{source_group},{products},', f'{source_group},{ui_ref},{products},')
ui_product = add("ui-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = YubaiUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[products] = objects[products].replace(f'{product},', f'{product},{ui_product},')
ui_sources = add("ui-test-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ui_file_build},); runOnlyForDeploymentPostprocessing = 0;')
ui_frameworks = add("ui-test-frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
ui_proxy = add("ui-test-proxy", f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Yubai;')
ui_dependency = add("ui-test-dependency", f'isa = PBXTargetDependency; target = {target}; targetProxy = {ui_proxy};')
ui_configs = [add('ui-config:' + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; IPHONEOS_DEPLOYMENT_TARGET = 18.0;
PRODUCT_BUNDLE_IDENTIFIER = app.yubai.personal.uitests; PRODUCT_NAME = "$(TARGET_NAME)";
SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SWIFT_VERSION = 5.0;
TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = Yubai; ONLY_ACTIVE_ARCH = YES;
}};''') for name in ['Debug', 'Release']]
ui_config_list = add('ui-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(ui_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
ui_target = add('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_config_list}; buildPhases = ({ui_sources},{ui_frameworks},); buildRules = (); dependencies = ({ui_dependency},); name = YubaiUITests; productName = YubaiUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
objects[project_id] = objects[project_id].replace(f'targets = ({target},);', f'targets = ({target},{ui_target},);')
content = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 77; objects = {\n'
content += '\n'.join(f'{key} = {{{value}}};' for key, value in objects.items())
content += f'\n}}; rootObject = {project_id}; }}\n'
(project / 'project.pbxproj').write_text(content)
schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Yubai.app" BlueprintName="Yubai" ReferencedContainer="container:Yubai.xcodeproj"/>'
test_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="YubaiUITests.xctest" BlueprintName="YubaiUITests" ReferencedContainer="container:Yubai.xcodeproj"/>'
(schemes / 'Yubai.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_reference}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
