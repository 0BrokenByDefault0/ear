"""Generate the small dependency-free Xcode project deterministically."""
import hashlib
from pathlib import Path
r=Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key,body): objects.append(f'{uid(key)} = {{ {body} }};'); return uid(key)
def array(items): return '('+', '.join(items)+',)'
swift=['AudioAnalyzer.swift', 'AudioFiles.swift', 'Design.swift', 'EarApp.swift', 'EarStore.swift', 'Experiments.swift', 'Models.swift', 'NotebookFiles.swift', 'StudyViews.swift']
resources=['Assets.xcassets','PrivacyInfo.xcprivacy','AeonNocturne-Regular.otf','GUST-FONT-LICENSE.txt','LPPL-1.3c.tex','README-Aeon-Nocturne.txt']
fileids=[]; sourcebuild=[]; resourcebuild=[]
for f in swift+resources:
    kind='sourcecode.swift' if f.endswith('.swift') else 'folder.assetcatalog' if f.endswith('xcassets') else 'text.json' if f.endswith('json') else 'file' if f.endswith('otf') else 'text.xml'
    ref=obj(f,'isa = PBXFileReference; lastKnownFileType = '+kind+'; path = '+f+'; sourceTree = "<group>";')
    fileids.append(ref)
    b=obj(f+'build',f'isa = PBXBuildFile; fileRef = {ref};')
    (sourcebuild if f in swift else resourcebuild).append(b)
appref=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = EAR.app; sourceTree = BUILT_PRODUCTS_DIR;')
testref=obj('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = EARUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
appgroup=obj('appgroup',f'isa = PBXGroup; children = {array(fileids)}; path = EAR; sourceTree = "<group>";')
testfile=obj('testfile','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SmokeTests.swift; sourceTree = "<group>";')
testbuild=obj('testbuild',f'isa = PBXBuildFile; fileRef = {testfile};')
testgroup=obj('testgroup',f'isa = PBXGroup; children = {array([testfile])}; path = EARUITests; sourceTree = "<group>";')
products=obj('products',f'isa = PBXGroup; children = {array([appref,testref])}; name = Products; sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = {array([appgroup,testgroup,products])}; sourceTree = "<group>";')
sources=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sourcebuild)}; runOnlyForDeploymentPostprocessing = 0;')
res=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resourcebuild)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks=obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
testsources=obj('testsources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array([testbuild])}; runOnlyForDeploymentPostprocessing = 0;')
common='CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SDKROOT = iphoneos; SWIFT_VERSION = 6.0; TARGETED_DEVICE_FAMILY = "1,2";'
projectconfigs=[]; appconfigs=[]; testconfigs=[]
for config in ['Debug','Release']:
    opt='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES;' if config=='Debug' else 'SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    projectconfigs.append(obj('project'+config,f'isa = XCBuildConfiguration; buildSettings = {{ {common} {opt} }}; name = {config};'))
    appconfigs.append(obj('app'+config,f'isa = XCBuildConfiguration; buildSettings = {{ ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = EAR/Info.plist; MARKETING_VERSION = 1.1; PRODUCT_BUNDLE_IDENTIFIER = com.aeon.ear; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; ENABLE_PREVIEWS = YES; }}; name = {config};'))
    testconfigs.append(obj('test'+config,f'isa = XCBuildConfiguration; buildSettings = {{ GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; PRODUCT_BUNDLE_IDENTIFIER = com.aeon.ear.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = EAR; }}; name = {config};'))
def configlist(name,configs): return obj(name,f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pc=configlist('pc',projectconfigs); ac=configlist('ac',appconfigs); tc=configlist('tc',testconfigs)
app=obj('app',f'isa = PBXNativeTarget; buildConfigurationList = {ac}; buildPhases = {array([sources,frameworks,res])}; buildRules = (); dependencies = (); name = EAR; productName = EAR; productReference = {appref}; productType = "com.apple.product-type.application";')
proxy=obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = EAR;')
dep=obj('dependency',f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
test=obj('tests',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = {array([testsources])}; buildRules = (); dependencies = {array([dep])}; name = EARUITests; productName = EARUITests; productReference = {testref}; productType = "com.apple.product-type.bundle.ui-testing";')
proj=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app} = {{ CreatedOnToolsVersion = 16.0; }}; {test} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app,test])};')
(r/'EAR.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+proj+'; }\n')
def reference(id,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:EAR.xcodeproj"/>'
(r/'EAR.xcodeproj/xcshareddata/xcschemes/EAR.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app,'EAR.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test,'EARUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'EAR.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'EAR.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated EAR.xcodeproj')
