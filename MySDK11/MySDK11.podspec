Pod::Spec.new do |spec|
    spec.name         = 'MySDK11'
    spec.version      = '0.0.11'
    spec.authors      = { 'John McIntosh' => 'johntmcintosh@gmail.com' }
    spec.license      = { :type => 'MIT' }
    spec.homepage     = 'https://github.com/johntmcintosh'
    spec.summary      = 'Testing'
    spec.source         = { :git => '' }
    spec.ios.deployment_target = '13.0'
    spec.ios.vendored_frameworks = 'MySDK11.xcframework'
  end
