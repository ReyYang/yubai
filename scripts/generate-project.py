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
# iOS and unsandboxed macOS share the iCloud-only file; iCloud.xcconfig selects the sandbox variants.
entitlements = add("icloud-entitlements", 'isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Yubai-iCloud.entitlements; sourceTree = "<group>";')
refs.append(entitlements)
for key, filename in [("mac-entitlements", "Yubai-macOS.entitlements"), ("mac-icloud-entitlements", "Yubai-macOS-iCloud.entitlements")]:
    refs.append(add(key, f'isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {filename}; sourceTree = "<group>";'))
config_ref = add("icloud-config", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/iCloud.xcconfig; sourceTree = "<group>";')
signing_ref = add("signing-config", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Signing.xcconfig; sourceTree = "<group>";')
source_group = add("app-group", f'isa = PBXGroup; children = ({",".join(refs)},); path = Sources/YubaiApp; sourceTree = "<group>";')
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Yubai.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = add("root-group", f'isa = PBXGroup; children = ({source_group},{config_ref},{signing_ref},{products},); sourceTree = "<group>";')
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
    IPHONEOS_DEPLOYMENT_TARGET = 26.0;
    MACOSX_DEPLOYMENT_TARGET = 14.0;
    MARKETING_VERSION = 2.0.0;
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
    configs.append(add("target-config:" + name, f'isa = XCBuildConfiguration; baseConfigurationReference = {config_ref}; buildSettings = {{{settings} ONLY_ACTIVE_ARCH = {"YES" if name == "Debug" else "NO"}; SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quote("$(inherited) DEBUG" if name == "Debug" else "$(inherited)")}; SWIFT_OPTIMIZATION_LEVEL = {quote(optimization)}; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; }}; name = {name};'))
config_list = add("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add("target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = Yubai; packageProductDependencies = ({dependency},); productName = Yubai; productReference = {product}; productType = "com.apple.product-type.application";')
project_configs = [add("project-config:" + name, f'isa = XCBuildConfiguration; buildSettings = {{CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; ENABLE_USER_SCRIPT_SANDBOXING = YES; ENABLE_TESTABILITY = {"YES" if name == "Debug" else "NO"};}}; name = {name};') for name in ['Debug', 'Release']]
project_config_list = add("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project_id = add("project", f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 2640; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 16.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base,); mainGroup = {group}; packageReferences = ({package},); productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
ui_ref = add("ui-test-file", 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/YubaiUITests/AppFlowTests.swift; sourceTree = "<group>";')
ui_file_build = add("ui-test-file-build", f'isa = PBXBuildFile; fileRef = {ui_ref};')
motion_ref = ident("Sources/YubaiApp/MotionState.swift")
motion_ui_build = add("motion-ui-test-build", f'isa = PBXBuildFile; fileRef = {motion_ref};')
objects[group] = objects[group].replace(f'{source_group},{config_ref},{signing_ref},{products},', f'{source_group},{config_ref},{signing_ref},{ui_ref},{products},')
ui_product = add("ui-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = YubaiUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[products] = objects[products].replace(f'{product},', f'{product},{ui_product},')
ui_sources = add("ui-test-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ui_file_build},{motion_ui_build},); runOnlyForDeploymentPostprocessing = 0;')
ui_frameworks = add("ui-test-frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
ui_proxy = add("ui-test-proxy", f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Yubai;')
ui_dependency = add("ui-test-dependency", f'isa = PBXTargetDependency; target = {target}; targetProxy = {ui_proxy};')
ui_configs = [add('ui-config:' + name, f'''isa = XCBuildConfiguration; baseConfigurationReference = {signing_ref}; name = {name}; buildSettings = {{
CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; IPHONEOS_DEPLOYMENT_TARGET = 26.0;
PRODUCT_BUNDLE_IDENTIFIER = app.yubai.personal.uitests; PRODUCT_NAME = "$(TARGET_NAME)";
SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SWIFT_VERSION = 5.0;
TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = Yubai; ONLY_ACTIVE_ARCH = YES;
}};''') for name in ['Debug', 'Release']]
ui_config_list = add('ui-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(ui_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
ui_target = add('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_config_list}; buildPhases = ({ui_sources},{ui_frameworks},); buildRules = (); dependencies = ({ui_dependency},); name = YubaiUITests; productName = YubaiUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
objects[project_id] = objects[project_id].replace(f'targets = ({target},);', f'targets = ({target},{ui_target},);')
# Core fixtures belong only to the unit-test target, including SampleData.swift.
core_test_refs, core_test_builds = [], []
for file in sorted((root / "Tests/YubaiCoreTests").glob("*.swift")):
    ref = add("core-test-ref:" + file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.name)}; sourceTree = "<group>";')
    core_test_refs.append(ref)
    core_test_builds.append(add("core-test-build:" + file.name, f'isa = PBXBuildFile; fileRef = {ref};'))
fixtures_ref = add("core-test-fixtures", 'isa = PBXFileReference; lastKnownFileType = folder; path = Fixtures; sourceTree = "<group>";')
fixtures_build = add("core-test-fixtures-build", f'isa = PBXBuildFile; fileRef = {fixtures_ref};')
core_test_refs.append(fixtures_ref)
core_test_group = add("core-test-group", f'isa = PBXGroup; children = ({",".join(core_test_refs)},); path = Tests/YubaiCoreTests; sourceTree = "<group>";')
objects[group] = objects[group].replace(f'{source_group},', f'{source_group},{core_test_group},')
core_test_product = add("core-test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = YubaiCoreTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[products] = objects[products].replace(f'{product},', f'{product},{core_test_product},')
core_test_sources = add("core-test-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(core_test_builds)},); runOnlyForDeploymentPostprocessing = 0;')
core_test_dependency = add("core-test-package", f'isa = XCSwiftPackageProductDependency; package = {package}; productName = YubaiCore;')
core_test_link = add("core-test-link", f'isa = PBXBuildFile; productRef = {core_test_dependency};')
core_test_frameworks = add("core-test-frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_test_link},); runOnlyForDeploymentPostprocessing = 0;')
core_test_resources = add("core-test-resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({fixtures_build},); runOnlyForDeploymentPostprocessing = 0;')
core_test_configs = [add("core-test-config:" + name, f'''isa = XCBuildConfiguration; baseConfigurationReference = {signing_ref}; name = {name}; buildSettings = {{
CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; IPHONEOS_DEPLOYMENT_TARGET = 26.0; MACOSX_DEPLOYMENT_TARGET = 14.0;
PRODUCT_BUNDLE_IDENTIFIER = app.yubai.personal.coretests; PRODUCT_NAME = "$(TARGET_NAME)";
SDKROOT = auto; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"; SWIFT_VERSION = 5.0;
SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quote("DEBUG" if name == "Debug" else "")};
TARGETED_DEVICE_FAMILY = "1,2"; ONLY_ACTIVE_ARCH = YES;
}};''') for name in ["Debug", "Release"]]
core_test_config_list = add("core-test-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(core_test_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
core_test_target = add("core-test-target", f'isa = PBXNativeTarget; buildConfigurationList = {core_test_config_list}; buildPhases = ({core_test_sources},{core_test_frameworks},{core_test_resources},); buildRules = (); dependencies = (); name = YubaiCoreTests; packageProductDependencies = ({core_test_dependency},); productName = YubaiCoreTests; productReference = {core_test_product}; productType = "com.apple.product-type.bundle.unit-test";')
objects[project_id] = objects[project_id].replace(f'targets = ({target},{ui_target},);', f'targets = ({target},{ui_target},{core_test_target},);')
content = '// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 77; objects = {\n'
content += '\n'.join(f'{key} = {{{value}}};' for key, value in objects.items())
content += f'\n}}; rootObject = {project_id}; }}\n'
(project / 'project.pbxproj').write_text(content)
schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Yubai.app" BlueprintName="Yubai" ReferencedContainer="container:Yubai.xcodeproj"/>'
test_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="YubaiUITests.xctest" BlueprintName="YubaiUITests" ReferencedContainer="container:Yubai.xcodeproj"/>'
core_test_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{core_test_target}" BuildableName="YubaiCoreTests.xctest" BlueprintName="YubaiCoreTests" ReferencedContainer="container:Yubai.xcodeproj"/>'
(schemes / 'Yubai.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{core_test_reference}</TestableReference><TestableReference skipped="NO">{test_reference}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
