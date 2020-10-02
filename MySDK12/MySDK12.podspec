Pod::Spec.new do |spec|
    spec.name         = 'MySDK12'
    spec.version      = '0.0.12'
    spec.authors      = { 'John McIntosh' }
    spec.license      = { :type => 'MIT' }
    spec.homepage     = 'https://github.com/johntmcintosh'
    spec.summary      = 'Testing'
    spec.source         = { :git => '' }
    spec.vendored_frameworks = 'MySDK12.xcframework'
  end
