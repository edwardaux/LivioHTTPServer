Pod::Spec.new do |spec|
  spec.name         = 'SuperSocket'
  spec.version      = '8.1.0'
  spec.license      = { :type => 'Public Domain', :file => 'LICENSE' }
  spec.homepage     = 'https://github.com/livio/supersocket'
  spec.authors      = { 'Joel Fischer' => 'joel@livio.io' }
  spec.summary      = 'Asynchronous socket networking library forked from CocoaAsyncSocket'
  spec.source       = { :git => 'https://github.com/livio/supersocket.git', :tag => spec.version.to_s }
  spec.source_files = 'SuperSocket/*.{h,m}'
  spec.ios.deployment_target = '8.0'
  spec.osx.deployment_target = '10.9'
end
