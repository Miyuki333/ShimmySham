DUMPBIN = "C:\\Program Files (x86)\\Microsoft Visual Studio 12.0\\VC\\bin\\dumpbin.exe"

require "stringio"

input_path = ARGV[0]
raise("Error: No input path given.") unless input_path
raise("Error: \"#{input_path}\" does not exist.") unless File.exist?(input_path)
input_path = File.expand_path(input_path)
input_name = File.basename(input_path)

output_path = File.expand_path(ARGV[1] || Dir.pwd)
output_name = File.basename(input_path, ".*")

raise("Error: dumpbin path \"#{DUMPBIN}\" does not exist.") unless File.exist?(DUMPBIN)
Dir.chdir(File.dirname(DUMPBIN))

output = `\"#{DUMPBIN}\" /exports \"#{input_path}\"`
File.open(File.join(output_path, output_name) + ".txt", "w") { | file | file.write(output) }
lines = output.split("\n")

matches = [/Microsoft \(R\) COFF\/PE Dumper Version/,
  /Copyright \(C\) Microsoft Corporation\..*All rights reserved\./,
  //,
  //,
  /Dump of file/,
  //,
  /File Type\:/,
  //,
  /Section contains the following exports for/,
  //,
  /characteristics/,
  /time date stamp/,
  /version/,
  /ordinal base/,
  /number of functions/,
  /number of names/,
  //,
  /ordinal.*hint.*RVA.*name/,
  //]

matches.each_with_index do | match |
  raise("Error: Invalid dumpbin output \"#{lines.first}\".") unless lines.first =~ match
  lines.shift
end

modules = [output_name]
exports = []

lines.each do | line |
  line = line.gsub(/\s+/m, " ").split(" ", 4)
  
  if line == []
    break
  elsif line[2] =~ /\[NONAME\]/
    ordinal = line[0]
    hint = nil
    rva = line[1]
    name = nil
  elsif line.length == 4 and line[0].to_i.to_s == line[0]
    ordinal = line[0]
    hint = line[1]
    match = line[3].match(/\(forwarded to (.*)\)/)
    if match != nil
      forward = match[1]
      module_name = forward.split(".", 2)[0]
      modules << module_name if modules.include?(module_name) != true
      rva = nil
      name = line[2]
    else
      rva = line[2]
      name = line[3]
    end
  else
    raise ("Error: Invalid dumpbin output \"#{line}\".")
  end
  
  exports << {:ordinal => ordinal, :hint => hint, :rva => rva, :name => name, :forward => forward}
end

File.open(File.join(output_path, output_name) + ".def", "w") do | file |
  
  file.puts("LIBRARY #{output_name}")
  file.puts("")
  file.puts("EXPORTS")
  file.puts("")
  
  exports.each do | export |
    if export[:name]
      file.puts("#{export[:name]} = _#{export[:name]} @#{export[:ordinal]}")
    else
      file.puts("Ordinal_#{export[:ordinal]} = _Ordinal_#{export[:ordinal]} @#{export[:ordinal]}")
    end
  end
  
end

File.open(File.join(output_path, output_name) + ".asm", "w") do | file |
  
  file.puts("%ifidn __OUTPUT_FORMAT__, win32")
  file.puts("\t")
  file.puts("\t%macro shim 1")
  file.puts("\t\t")
  file.puts("\t\tglobal __%1@0")
  file.puts("\t\texport __%1@0")
  file.puts("\t\t")
  file.puts("\t\t__%1@0:")
  file.puts("\t\t\textern _O_%1")
  file.puts("\t\t\tjmp [_O_%1]")
  file.puts("\t\t")
  file.puts("\t%endmacro")
  file.puts("\t")
  file.puts("\t%macro override 1-2")
  file.puts("\t\t")
  file.puts("\t\tglobal __%1@0")
  file.puts("\t\texport __%1@0")
  file.puts("\t\t")
  file.puts("\t\t__%1@0:")
  file.puts("\t\t\textern _I_%1%2")
  file.puts("\t\t\tjmp _I_%1%2")
  file.puts("\t\t")
  file.puts("\t%endmacro")
  file.puts("\t")
  file.puts("%elifidn __OUTPUT_FORMAT__, win64")
  file.puts("\t")
  file.puts("\t%macro shim 1")
  file.puts("\t\t")
  file.puts("\t\tglobal _%1")
  file.puts("\t\texport _%1")
  file.puts("\t\t")
  file.puts("\t\t_%1:")
  file.puts("\t\t\textern O_%1")
  file.puts("\t\t\tmov rax, O_%1")
  file.puts("\t\t\tjmp [rax]")
  file.puts("\t\t")
  file.puts("\t%endmacro")
  file.puts("\t")
  file.puts("\t%macro override 1-2")
  file.puts("\t\t")
  file.puts("\t\tglobal _%1")
  file.puts("\t\texport _%1")
  file.puts("\t\t")
  file.puts("\t\t_%1:")
  file.puts("\t\t\textern I_%1")
  file.puts("\t\t\tmov rax, I_%1")
  file.puts("\t\t\tjmp rax")
  file.puts("\t\t")
  file.puts("\t%endmacro")
  file.puts("\t")
  file.puts("%endif")
  
  file.puts("")
  file.puts("section .text")
  file.puts("")
  
  exports.each do | export |
    name = export[:name] || "Ordinal_#{export[:ordinal]}"
    file.puts("shim #{name}")
  end
  
end

File.open(File.join(output_path, output_name) + ".cpp", "w") do | file |
  
  file.puts("#include <windows.h>")
  file.puts("#include <stdio.h>")
  file.puts("")
  file.puts("static HINSTANCE g_hModule_#{modules.first} = 0;")
  file.puts("")
  file.puts("extern \"C\"")
  file.puts("{")
  file.puts("\t")
  
  exports.each do | export |
    if export[:name]
      file.puts("\tFARPROC O_#{export[:name]};")
    else
      file.puts("\tFARPROC O_Ordinal_#{export[:ordinal]};")
    end
  end
  
  file.puts("\t")
  file.puts("}")
  file.puts("")
  file.puts("BOOL WINAPI DllMain(HINSTANCE hI, DWORD reason, LPVOID notUsed)")
  file.puts("{")
  file.puts("\tif (reason == DLL_PROCESS_ATTACH)")
  file.puts("\t{")
  file.puts("\t\t#ifdef _DEBUG")
  file.puts("\t\t\tFILE * stream;")
  file.puts("\t\t\tAllocConsole();")
  file.puts("\t\t\tfreopen_s(&stream, \"CONIN$\", \"r\", stdin);")
  file.puts("\t\t\tfreopen_s(&stream, \"CONOUT$\", \"w\", stdout);")
  file.puts("\t\t\tfreopen_s(&stream, \"CONOUT$\", \"w\", stderr);")
  file.puts("\t\t#endif")
  file.puts("\t")
  file.puts("\t\tg_hModule_#{modules.first} = LoadLibraryA(\"#{modules.first}.dll\");")
  file.puts("\t\tif (!g_hModule_#{modules.first}) return FALSE;")
  file.puts("\t\t")
  
  exports.each do | export |
    #module_name = export[:forward] ? export[:forward].split(".", 2)[0] : modules.first
    module_name = modules.first
    if export[:name]
      file.puts("\t\tO_#{export[:name]} = GetProcAddress(g_hModule_#{module_name}, \"#{export[:name]}\");")
    else
      file.puts("\t\tO_Ordinal_#{export[:ordinal]} = GetProcAddress(g_hModule_#{module_name}, LPCSTR(MAKEINTRESOURCE(#{export[:ordinal]})));")
    end
  end
  
  file.puts("\t\t")
  file.puts("\t\treturn TRUE;")
  file.puts("\t}")
  file.puts("\telse if (reason == DLL_PROCESS_DETACH)")
  file.puts("\t{")
  file.puts("\t\tFreeLibrary(g_hModule_#{modules.first});")
  file.puts("\t\treturn TRUE;")
  file.puts("\t}")
  file.puts("}")
  
end