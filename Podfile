source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '14.0'
use_frameworks!

target 'shafinMultitool' do
    pod 'ARVideoKit', '~> 1.5.51'
    pod 'SnapKit', '~> 5.6.0'
end

target 'shafinMultitoolTests' do
    pod 'SnapKit', '~> 5.6.0'
end

post_install do |installer|
  minimum_ios_version = Gem::Version.new('12.0')

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      current_value = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
      current_version = current_value ? Gem::Version.new(current_value) : Gem::Version.new('0')

      if current_version < minimum_ios_version
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = minimum_ios_version.to_s
      end
    end
  end
end
