Pod::Spec.new do |s|
  s.name             = 'pilar_print'
  s.version          = '0.1.0'
  s.summary          = 'Virtual printer management for PILAR ERP'
  s.homepage         = 'https://galapagos.tech'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Galapagos Tech' => 'dev@galapagos.tech' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
