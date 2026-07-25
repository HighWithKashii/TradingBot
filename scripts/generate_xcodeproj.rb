#!/usr/bin/env ruby
# Regenerates BeanFocus.xcodeproj from the BeanFocus/ source tree.
#
# Why this script exists: the project was authored without access to Xcode
# itself, so instead of hand-crafting (and risking corrupting) project.pbxproj,
# we use the battle-tested `xcodeproj` Ruby gem to assemble a valid project
# programmatically from the folder structure on disk. Run this again any time
# files are added/removed outside of Xcode:
#
#   gem install xcodeproj
#   ruby scripts/generate_xcodeproj.rb
#
require 'xcodeproj'
require 'pathname'

ROOT = Pathname.new(File.expand_path('..', __dir__))
SOURCE_ROOT = ROOT + 'BeanFocus'
PROJECT_PATH = ROOT + 'BeanFocus.xcodeproj'

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)

target = project.new_target(:application, 'BeanFocus', :ios, '17.0', nil, :swift)

# ---------------------------------------------------------------------------
# Walk BeanFocus/ and mirror the folder structure as PBXGroups, adding every
# .swift file to Compile Sources and every .xcassets/.entitlements as a
# resource / plain reference respectively.
# ---------------------------------------------------------------------------
# NOTE: every path passed to new_group/new_reference below is relative to
# its *immediate parent* (not absolute, not relative to the project root) -
# xcodeproj resolves the full location by walking up the group chain. Using
# relative basenames keeps the generated project portable across machines.
root_group = project.main_group.new_group('BeanFocus', 'BeanFocus')

def add_directory(project, target, group, dir)
  Pathname.new(dir).children.sort.each do |child|
    if child.directory?
      if child.extname == '.xcassets'
        ref = group.new_reference(child.basename.to_s)
        target.resources_build_phase.add_file_reference(ref)
      else
        subgroup = group.new_group(child.basename.to_s, child.basename.to_s)
        add_directory(project, target, subgroup, child)
      end
    else
      case child.extname
      when '.swift'
        ref = group.new_reference(child.basename.to_s)
        target.source_build_phase.add_file_reference(ref)
      when '.entitlements'
        group.new_reference(child.basename.to_s)
      end
    end
  end
end

add_directory(project, target, root_group, SOURCE_ROOT)

# ---------------------------------------------------------------------------
# Link HealthKit explicitly (harmless even though Swift autolinks system
# frameworks) so the capability is unambiguous when opened in Xcode.
# ---------------------------------------------------------------------------
frameworks_group = project.frameworks_group
healthkit_ref = frameworks_group.new_reference('System/Library/Frameworks/HealthKit.framework')
healthkit_ref.source_tree = 'SDKROOT'
target.frameworks_build_phase.add_file_reference(healthkit_ref)

# ---------------------------------------------------------------------------
# Build settings
# ---------------------------------------------------------------------------
entitlements_path = 'BeanFocus/Resources/BeanFocus.entitlements'

common_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER' => 'com.beanfocus.app',
  'PRODUCT_NAME' => 'BeanFocus',
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'CODE_SIGN_ENTITLEMENTS' => entitlements_path,
  'CODE_SIGN_STYLE' => 'Automatic',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'BeanFocus',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' =>
    'BeanFocus liest deine Herzfrequenz, HRV, Schlaf- und Aktivitätsdaten, um Recovery, Strain und Stress zu berechnen.',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' =>
    'BeanFocus kann Trainingseinheiten in Health speichern, die du in der App aufzeichnest.',
  'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
  'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
  'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
  'INFOPLIST_KEY_UIUserInterfaceStyle' => 'Dark',
  'ENABLE_PREVIEWS' => 'YES',
  'SUPPORTS_MACCATALYST' => 'NO',
  'DEVELOPMENT_TEAM' => ''
}

target.build_configurations.each do |config|
  common_settings.each { |k, v| config.build_settings[k] = v }
end

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end

project.save

puts "Generated #{PROJECT_PATH}"
