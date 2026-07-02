#!/usr/bin/env ruby
# 用 xcodeproj 安全地把 GpuPixel framework 链接进 LumiCue target。
require 'xcodeproj'

proj_path = 'LumiCue.xcodeproj'
proj = Xcodeproj::Project.open(proj_path)
target = proj.targets.find { |t| t.name == 'LumiCue' }
abort('找不到 LumiCue target') unless target

# 1. framework 文件引用(放 Frameworks 组)
fw_rel = 'LumiCue/ThirdParty/GpuPixel/gpupixel.framework'
existing = proj.files.find { |f| f.path == fw_rel || (f.path && f.path.end_with?('gpupixel.framework')) }
fw_ref = existing || proj.frameworks_group.new_reference(fw_rel)

# 2. Link Binary With Libraries
unless target.frameworks_build_phase.files_references.include?(fw_ref)
  target.frameworks_build_phase.add_file_reference(fw_ref)
end

# 3. Embed Frameworks (copy 到 .app/Contents/Frameworks + 签名)
embed = target.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '10' } # 10 = Frameworks
unless embed
  embed = target.new_copy_files_build_phase('Embed Frameworks')
  embed.symbol_dst_subfolder_spec = :frameworks
end
unless embed.files_references.include?(fw_ref)
  bf = embed.add_file_reference(fw_ref)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

# 4. build settings(所有配置)
target.build_configurations.each do |c|
  s = c.build_settings
  fsp = Array(s['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)'])
  fsp << '$(SRCROOT)/LumiCue/ThirdParty/GpuPixel' unless fsp.include?('$(SRCROOT)/LumiCue/ThirdParty/GpuPixel')
  s['FRAMEWORK_SEARCH_PATHS'] = fsp

  hsp = Array(s['HEADER_SEARCH_PATHS'] || ['$(inherited)'])
  inc = '$(SRCROOT)/LumiCue/ThirdParty/GpuPixel/include'
  hsp << inc unless hsp.include?(inc)
  s['HEADER_SEARCH_PATHS'] = hsp

  s['SWIFT_OBJC_BRIDGING_HEADER'] = 'LumiCue/LumiCue-Bridging-Header.h'
  s['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
  s['CLANG_CXX_LIBRARY'] = 'libc++'
end

proj.save
puts '✅ pbxproj 配置完成: 链接gpupixel.framework + Embed + search paths + bridging header + C++17'
