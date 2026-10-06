import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// Dependency-free, deterministic Xcode project generator.
const root = path.resolve(import.meta.dirname, '..');
const id = name => crypto.createHash('sha256').update(name).digest('hex').slice(0, 24).toUpperCase();
const quote = value => JSON.stringify(value);
const objects = [];
const add = (name, value) => { objects.push(`${id(name)} = { ${value} };`); return id(name); };
const list = items => `(${items.join(', ')},)`;
const walk = dir => fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry =>
  entry.isDirectory() ? walk(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
const appSources = walk('CommuteFocus').filter(file => file.endsWith('.swift')).sort();
const tests = walk('CommuteFocusTests').filter(file => file.endsWith('.swift')).sort();
const resources = ['CommuteFocus/PrivacyInfo.xcprivacy'];
const extra = ['Config/Development.xcconfig', 'CommuteFocus/Info.plist', 'README.md'];
const refs = [...appSources, ...tests, ...resources, ...extra].map(file => {
  const type = file.endsWith('.swift') ? 'sourcecode.swift' : file.endsWith('.xcconfig') ? 'text.xcconfig' : file.endsWith('.md') ? 'net.daringfireball.markdown' : 'text.plist.xml';
  return add(`file:${file}`, `isa = PBXFileReference; lastKnownFileType = ${type}; path = ${quote(file)}; sourceTree = SOURCE_ROOT;`);
});
const appProduct = add('product:app', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = CommuteFocus.app; sourceTree = BUILT_PRODUCTS_DIR;');
const testProduct = add('product:tests', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CommuteFocusTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
const products = add('products', `isa = PBXGroup; children = ${list([appProduct, testProduct])}; name = Products; sourceTree = "<group>";`);
const main = add('main', `isa = PBXGroup; children = ${list([...refs, products])}; sourceTree = "<group>";`);
function phase(name, type, files) {
  const builds = files.map(file => add(`build:${name}:${file}`, `isa = PBXBuildFile; fileRef = ${id(`file:${file}`)};`));
  return add(name, `isa = ${type}; buildActionMask = 2147483647; files = (${builds.join(', ')}${builds.length ? ',' : ''}); runOnlyForDeploymentPostprocessing = 0;`);
}
const appPhase = phase('sources:app', 'PBXSourcesBuildPhase', appSources);
const testsPhase = phase('sources:tests', 'PBXSourcesBuildPhase', tests);
const resourcePhase = phase('resources', 'PBXResourcesBuildPhase', resources);
const frameworks = phase('frameworks', 'PBXFrameworksBuildPhase', []);
function configurations(name, settings) {
  const configs = ['Debug', 'Release'].map(mode => add(`config:${name}:${mode}`,
    `isa = XCBuildConfiguration; baseConfigurationReference = ${id('file:Config/Development.xcconfig')}; buildSettings = {
       ${settings} SWIFT_OPTIMIZATION_LEVEL = ${quote(mode === 'Debug' ? '-Onone' : '-O')};
       ${mode === 'Debug' ? 'ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";' : 'SWIFT_COMPILATION_MODE = wholemodule;'}
       }; name = ${mode};`));
  return add(`configs:${name}`, `isa = XCConfigurationList; buildConfigurations = ${list(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
const projectConfig = configurations('project', 'SDKROOT = iphoneos; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; GCC_C_LANGUAGE_STANDARD = gnu17;');
const appConfig = configurations('app', 'PRODUCT_BUNDLE_IDENTIFIER = com.example.CommuteFocus; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = CommuteFocus/Info.plist; GENERATE_INFOPLIST_FILE = NO; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SWIFT_EMIT_LOC_STRINGS = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";');
const testsConfig = configurations('tests', 'PRODUCT_BUNDLE_IDENTIFIER = com.example.CommuteFocusTests; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CommuteFocus.app/CommuteFocus"; BUNDLE_LOADER = "$(TEST_HOST)"; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";');
const proxy = add('proxy', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('target:app')}; remoteInfo = CommuteFocus;`);
const dependency = add('dependency', `isa = PBXTargetDependency; target = ${id('target:app')}; targetProxy = ${proxy};`);
add('target:app', `isa = PBXNativeTarget; buildConfigurationList = ${appConfig}; buildPhases = ${list([appPhase, frameworks, resourcePhase])}; buildRules = (); dependencies = (); name = CommuteFocus; productName = CommuteFocus; productReference = ${appProduct}; productType = "com.apple.product-type.application";`);
add('target:tests', `isa = PBXNativeTarget; buildConfigurationList = ${testsConfig}; buildPhases = ${list([testsPhase])}; buildRules = (); dependencies = ${list([dependency])}; name = CommuteFocusTests; productName = CommuteFocusTests; productReference = ${testProduct}; productType = "com.apple.product-type.bundle.unit-test";`);
add('project', `isa = PBXProject; attributes = { LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES; TargetAttributes = { ${id('target:app')} = { CreatedOnToolsVersion = 16.0; }; ${id('target:tests')} = { CreatedOnToolsVersion = 16.0; TestTargetID = ${id('target:app')}; }; }; }; buildConfigurationList = ${projectConfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = ${main}; productRefGroup = ${products}; projectDirPath = ""; projectRoot = ""; targets = ${list([id('target:app'), id('target:tests')])};`);
const projectDir = path.join(root, 'CommuteFocus.xcodeproj');
fs.mkdirSync(path.join(projectDir, 'xcshareddata/xcschemes'), { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), `// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n${objects.join('\n')}\n}; rootObject = ${id('project')}; }\n`);
const buildable = (name, product) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(`target:${name}`)}" BuildableName="${product}" BlueprintName="${name === 'app' ? 'CommuteFocus' : 'CommuteFocusTests'}" ReferencedContainer="container:CommuteFocus.xcodeproj"/>`;
fs.writeFileSync(path.join(projectDir, 'xcshareddata/xcschemes/CommuteFocus.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${buildable('app', 'CommuteFocus.app')}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${buildable('tests', 'CommuteFocusTests.xctest')}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('app', 'CommuteFocus.app')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable('app', 'CommuteFocus.app')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>`);
console.log(`Generated Xcode project: ${appSources.length} app sources, ${tests.length} test sources.`);
