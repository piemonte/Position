Pod::Spec.new do |s|
  s.name = 'Position'
  s.version = '0.10.0'
  s.license = 'MIT'
  s.summary = 'Efficient location positioning in Swift'
  s.homepage = 'https://github.com/piemonte/Position'
  s.social_media_url = 'https://twitter.com/piemonte'
  s.authors = { 'patrick piemonte' => "hello@patrickpiemonte.com" }
  s.source = { :git => 'https://github.com/piemonte/Position.git', :tag => s.version }
  s.ios.deployment_target = '15.0'
  s.source_files = 'Sources/*.swift'
  s.requires_arc = true
  s.swift_version = '5.5'
end
