Pod::Spec.new do |s|
  s.name         = "CAMKStoreKit"
  s.version      = "5.0.7"
  s.summary      = "My fork of MKStoreKit"

  s.description  = <<-DESC
                   My fork of MKStoreKit. It has only the features I'm interested in.
				   This was created because the MKStoreKit seems abandoned but I still use it in my apps.
				   Support was lacking for the new methods of IAP where purchases can be deferred until a parent approves them.
				   Also there were bugs to do with 64 bit code.
                   DESC

  s.homepage     = "http://www.cushwayapps.com"

  s.license      = { :type => 'Private', :file => 'licence.md' }
  
  s.author             = { "Alan Cushway" => "acushway@hotmail.com" }

  s.platform     = :ios, "7.0"

  s.source       = { :git => "https://github.com/acushway/MKStoreKit.git", :tag => s.version.to_s }

  s.source_files  = "*.{h,m}", "**/*.{h,m}"
  s.exclude_files = ".gitignore", "MKStoreKitConfigs.plist", "README.mdown"

  s.public_header_files = "*.h"

  s.framework  = "StoreKit"

  s.requires_arc = true

end
