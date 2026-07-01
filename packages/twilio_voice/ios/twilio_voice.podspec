#
# Twilio Voice Flutter wrapper — CocoaPods plugin spec.
# Pulls the native TwilioVoice xcframework as a transitive dependency.
#
Pod::Spec.new do |s|
  s.name             = 'twilio_voice'
  s.version          = '0.0.1'
  s.summary          = 'Flutter wrapper around the native Twilio Voice SDK.'
  s.description      = 'Outbound-call wrapper over the Twilio Voice iOS SDK.'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Twilio Temp' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'TwilioVoice', '~> 6.13'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
