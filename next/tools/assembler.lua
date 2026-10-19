local int,util=require('int64'),require('tool_util')
local manifest=require('opcodes')
local M={}
local instruction_names={}
for _,instruction in ipairs(manifest.ops) do
    if instruction.kind~=manifest.kind.EXT then instruction_names[instruction.name]=instruction end
end
for _,instruction in ipairs(manifest.ext_ops) do
    for _,stack in ipairs{'A','B'} do
        local selected=util.copy(instruction)
        selected.name=instruction.name..'_'..stack
        selected.opcode=stack=='A' and 0xf8 or 0xf9
        selected.stack=manifest.stack[stack]
        instruction_names[selected.name]=selected
    end
end
function M.opcodes() return instruction_names end
local function identifier(name) return name and name:match('^[A-Za-z_][A-Za-z_0-9]*$')~=nil end
local function integer(text,width,signed)
    local value,negative=int.parse(text)
    if not int.fits(value,negative,width,signed or false) then error(text..' does not fit '..(signed and 'i' or 'u')..width,0) end
    return value
end
local function small(text,width) return tonumber(integer(text,width,false)) end
local function kinds(text,count)
    text=text=='-' and '' or text
    if #text~=count or text:find('[^iaf]') then error('kind string requires one i/a/f per cell; use - for zero cells',0) end
    return (text:gsub('.',function(kind) return string.char(kind=='a' and 1 or kind=='f' and 2 or 0) end))
end
local function tokens(text)
    local result={};for token in text:gsub(',',' '):gmatch('%S+') do result[#result+1]=token end;return result
end
function M.assemble(source)
    local chunks,functions,function_names,labels,exports,fixups={},{},{},{},{},{}
    local signatures,sites,relocations,externs,extern_names={},{},{},{},{}
    local writable,readonly,annotations,c_entries={},{},{},{}
    local line_to_offset,offset_to_line={},{}
    local profile,pc,image_bytes=1,0,0
    local profile_declared,current,pending_kind,line_number
    line_number=0
    local function emit(bytes) chunks[#chunks+1]=bytes;pc=pc+#bytes end
    local function pack(text,width,signed) emit(int.pack(integer(text,width,signed),width/8)) end
    local function fixup(target,width,finish,call)
        fixups[#fixups+1]={offset=pc,target=target,width=width,finish=finish,owner=current,call=call,line=line_number}
        emit(string.rep('\0',width))
    end
    for raw in (source..'\n'):gmatch('(.-)\n') do
        line_number=line_number+1;local start=pc
        local ok,message=pcall(function()
            local line=raw:gsub(';.*$',''):match('^%s*(.-)%s*$')
            if line=='' then return end
            local words=tokens(line);local directive=words[1]
            if directive=='.profile' then
                local profiles={integer=1,memory=2,callables=3,foreign=4}
                if profile_declared or current or #words~=2 or not profiles[words[2]] then error('use .profile integer|memory|callables|foreign before functions',0) end
                profile=profiles[words[2]];profile_declared=true;return
            elseif directive=='.extern' then
                if profile<4 or #words~=4 or not identifier(words[2]) or extern_names[words[2]]~=nil then error('use .extern name argument_kinds result_kind in foreign profile',0) end
                local arguments=words[3]=='-' and '' or words[3];local results=words[4]=='-' and '' or words[4]
                local integer_count=select(2,arguments:gsub('[ia]',''));local float_count=select(2,arguments:gsub('f',''))
                if #arguments>10 or #results>1 or integer_count>6 or float_count>4 then error('extern limit is six integer/address, four float arguments, and zero or one result',0) end
                local external={name=words[2],args=#arguments,results=#results,arg_kinds=kinds(arguments,#arguments),result_kinds=kinds(results,#results)}
                extern_names[words[2]]=#externs;externs[#externs+1]=external;return
            elseif directive=='.signature' then
                if profile<3 or (#words~=4 and #words~=6 and #words~=7) or not identifier(words[2]) or signatures[words[2]] then error('invalid .signature name args results [kinds kinds [hidden_bytes]]',0) end
                local arguments,results=small(words[3],8),small(words[4],8)
                signatures[words[2]]={args=arguments,results=results,hidden=words[7] and small(words[7],32) or 0,
                    arg_kinds=kinds(words[5] or string.rep('i',arguments),arguments),result_kinds=kinds(words[6] or string.rep('i',results),results)};return
            elseif directive=='.codeaddr' then
                if profile<3 or #words~=3 or not identifier(words[3]) then error('use .codeaddr writable_offset function in callable profile',0) end
                relocations[#relocations+1]={offset=small(words[2],32),name=words[3]};return
            elseif directive=='.centry' then
                if profile~=4 or #words~=3 or not identifier(words[3]) then error('use .centry writable_offset function in foreign profile',0) end
                c_entries[#c_entries+1]={offset=small(words[2],32),name=words[3]};return
            elseif directive=='.data' or directive=='.rodata' or directive=='.datazero' then
                if profile<2 or #words~=2 then error('image directives require a memory profile and one operand',0) end
                local bytes
                if directive=='.datazero' then
                    local count=small(words[2],32);if count>16*1024*1024-image_bytes then error('image exceeds 16 MiB',0) end
                    bytes=string.rep('\0',count)
                else
                    local hex=words[2]=='-' and '' or words[2]
                    if #hex%2~=0 or hex:find('[^0-9a-fA-F]') then error('image requires hexadecimal byte pairs',0) end
                    bytes=hex:gsub('..',function(byte) return string.char(tonumber(byte,16)) end)
                end
                image_bytes=image_bytes+#bytes;if image_bytes>16*1024*1024 then error('image exceeds 16 MiB',0) end
                local destination=directive=='.rodata' and readonly or writable;destination[#destination+1]=bytes;return
            elseif directive=='.loadkind' then
                local load_kinds={int=0,addr=1,float=2}
                if profile<2 or pending_kind~=nil or #words~=2 or load_kinds[words[2]]==nil then error('use .loadkind int|addr|float before a 64-bit memory load',0) end
                pending_kind=load_kinds[words[2]];return
            elseif directive=='.function' then
                if pending_kind~=nil then error('load kind annotation needs a following instruction',0) end
                if (#words~=4 and not(profile>=2 and (#words==6 or #words==7))) or not identifier(words[2]) or function_names[words[2]] then error('invalid or duplicate .function name arguments results [kinds kinds [hidden_bytes]]',0) end
                local arguments,results=small(words[3],8),small(words[4],8)
                current=#functions+1;function_names[words[2]]=current;labels[current]={}
                functions[current]={name=words[2],entry=pc,args=arguments,results=results,hidden=words[7] and small(words[7],32) or 0,
                    arg_kinds=kinds(words[5] or string.rep('i',arguments),arguments),result_kinds=kinds(words[6] or string.rep('i',results),results)};return
            elseif directive=='.export' then
                if (#words~=2 and #words~=3) or not identifier(words[2]) then error('use .export public_name [function_name]',0) end
                exports[#exports+1]={words[2],words[#words],line_number};return
            end
            if not current then error('an instruction needs a .function declaration',0) end
            if line:find(':',1,true) then
                local label,rest=line:match('^(.-):(.*)$')
                if not identifier(label) or labels[current][label] then error('invalid or duplicate label',0) end
                labels[current][label]=pc;words=tokens(rest);if #words==0 then return end
            end
            local name=words[1]:upper():gsub('%.','_');local arguments=util.slice(words,2)
            if name=='PUSH_A' or name=='PUSH_B' then
                if #arguments~=1 then error('PUSH needs one integer',0) end
                local bits=int.parse(arguments[1]);local signed=int.i(bits)
                local width=(signed>=-128 and signed<=127) and 8 or (signed>=-2147483648 and signed<=2147483647) and 32 or 64
                name='PUSH'..width..'_'..name:sub(-1);arguments={int.format(bits,true)}
            elseif name=='CGET_A' or name=='CGET_B' or name=='CSET_A' or name=='CSET_B' then
                if #arguments~=1 then error('context access needs a depth',0) end
                local depth=small(arguments[1],8);local get=name:sub(1,4)=='CGET';local family=get and 'CGET' or 'CSET'
                if depth<=(get and 1 or 0) then name=family..depth..'_'..name:sub(-1);arguments={}
                else name=family..'N_'..name:sub(-1) end
            end
            local instruction=instruction_names[name]
            if not instruction then error('unknown instruction '..name..'; selected forms require .A or .B',0) end
            if instruction.profile>profile then error(name..' requires a higher capability profile',0) end
            local kind,layout=instruction.kind,instruction.layout_name;local K=manifest.kind
            local expected=layout=='NONE' and 0 or layout=='U8_U8' and 2 or layout=='I8_I16' and 2 or 1
            if kind==K.CALL or kind==K.ICALL then expected=2 elseif kind==K.TCALL or kind==K.ITCALL then expected=3 elseif kind==K.SWITCH then expected=#arguments end
            if #arguments~=expected then error(name..' expects '..expected..' operands',0) end
            if pending_kind~=nil then annotations[#annotations+1]=int.pack(pc,4)..string.char(pending_kind);pending_kind=nil end
            local instruction_start=pc;local length=kind==K.SWITCH and 3+4*#arguments or instruction.len
            emit(string.char(instruction.opcode))
            if instruction.selector~=nil then emit(string.char(instruction.selector)) end
            if kind==K.SWITCH then
                if #arguments>65535 then error('SWITCH table exceeds u16 count',0) end
                emit(int.pack(#arguments,2));for _,target in ipairs(arguments) do fixup(target,4,instruction_start+length,false) end
            elseif kind==K.CALL or kind==K.TCALL then
                fixup(arguments[1],4,instruction_start+length,true)
                for index=2,#arguments do pack(arguments[index],8,false) end
            elseif kind==K.BRANCH or kind==K.JMP32 or kind==K.BRI then
                if kind==K.BRI then pack(arguments[1],8,true) end
                fixup(arguments[kind==K.BRI and 2 or 1],kind==K.JMP32 and 4 or 2,instruction_start+length,false)
            elseif kind==K.ICALL or kind==K.ITCALL then
                for index=1,#arguments-1 do pack(arguments[index],8,false) end
                sites[#sites+1]={offset=instruction_start,name=arguments[#arguments]}
            elseif kind==K.FCALL then
                local index=extern_names[arguments[1]];if index==nil then error('unknown extern '..arguments[1],0) end;emit(int.pack(index,2))
            elseif layout=='U8_U8' then pack(arguments[1],8,false);pack(arguments[2],8,false)
            elseif layout=='I8' then pack(arguments[1],8,true)
            elseif layout=='I32' then pack(arguments[1],32,true)
            elseif layout=='U64' then local bits=int.parse(arguments[1]);emit(int.pack(bits,8))
            elseif layout=='U8' then pack(arguments[1],8,false)
            elseif layout=='U16' then pack(arguments[1],16,false)
            elseif layout=='U32' then pack(arguments[1],32,false)
            elseif layout~='NONE' then error('unhandled operand layout '..layout,0) end
            if pc~=instruction_start+length then error('assembler length disagrees with manifest',0) end
        end)
        if not ok then error('line '..line_number..': '..tostring(message),0) end
        if pc>start then line_to_offset[line_number]=start;for offset=start,pc-1 do offset_to_line[offset]=line_number end end
    end
    if pending_kind~=nil then error('load kind annotation needs a following instruction',0) end
    local code=table.concat(chunks)
    for _,fix in ipairs(fixups) do
        local target
        if fix.call then local index=function_names[fix.target];target=index and functions[index].entry
        else target=labels[fix.owner][fix.target] end
        if target==nil then error('line '..fix.line..': unknown target '..fix.target,0) end
        local displacement=target-fix.finish;local bound=2^(fix.width*8-1)
        if displacement < -bound or displacement >= bound then error('line '..fix.line..': displacement out of range',0) end
        code=code:sub(1,fix.offset)..int.pack(displacement,fix.width)..code:sub(fix.offset+fix.width+1)
    end
    if #exports==0 and function_names.main then exports={{'main','main',0}} end
    local records={int.pack(#functions,4)}
    for _,fn in ipairs(functions) do
        for _,value in ipairs{fn.entry,fn.args,fn.results,fn.hidden} do records[#records+1]=int.pack(value,4) end
        if profile>=2 then records[#records+1]=fn.arg_kinds..fn.result_kinds end
    end
    local function entryRelocations(entries)
        local result={int.pack(#entries,4)}
        table.sort(entries,function(a,b)return a.offset<b.offset end)
        for _,entry in ipairs(entries) do
            local index=function_names[entry.name];if not index then error('unknown relocated function '..entry.name,0) end
            result[#result+1]=int.pack(entry.offset,4)..int.pack(index-1,4)
        end
        return table.concat(result)
    end
    local sections={table.concat(records),code};records={int.pack(#exports,4)}
    for _,export in ipairs(exports) do
        local index=function_names[export[2]];if not index then error('unknown exported function '..export[2],0) end
        if #export[1]>255 then error('export name exceeds 255 bytes',0) end
        records[#records+1]=int.pack(index-1,4)..int.pack(#export[1],2)..export[1]
    end
    sections[3]=table.concat(records)
    if profile>=2 then sections[4]=table.concat(writable);sections[5]=table.concat(readonly);sections[6]=int.pack(#annotations,4)..table.concat(annotations) end
    if profile>=3 then
        records={int.pack(#sites,4)}
        for _,site in ipairs(sites) do
            local signature=signatures[site.name] or (function_names[site.name] and functions[function_names[site.name]])
            if not signature then error('unknown indirect signature '..site.name,0) end
            for _,value in ipairs{site.offset,signature.args,signature.results,signature.hidden} do records[#records+1]=int.pack(value,4) end
            records[#records+1]=signature.arg_kinds..signature.result_kinds
        end
        sections[7]=table.concat(records)
        sections[8]=entryRelocations(relocations)
    end
    if profile>=4 then
        records={int.pack(#externs,4)}
        for _,external in ipairs(externs) do records[#records+1]=string.char(external.args,external.results)..int.pack(#external.name,2)..external.arg_kinds..external.result_kinds..external.name end
        sections[9]=table.concat(records)
    end
    -- Revision 7 adds C-entry metadata, not a different opcode map.
    local revision=manifest.revision
    if #c_entries>0 then revision=7;sections[10]=entryRelocations(c_entries) end
    local image='ABC2'..int.pack(revision,2)..string.char(8,profile)..int.pack(#sections,4)..int.pack(0,4)
    for tag,payload in ipairs(sections) do image=image..int.pack(tag,4)..int.pack(#payload,4)..payload end
    return image,{lineToOffset=line_to_offset,offsetToLine=offset_to_line}
end
return M
