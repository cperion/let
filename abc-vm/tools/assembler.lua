local int,util=require('int64'),require('tool_util')
local manifest=require('opcodes')
local ext_by_name={} for i,x in ipairs(manifest.ext_ops) do ext_by_name[x.name]={selector=i-1,length=x.len,family=x.family} end
local M, cached = {}, nil
local function identifier(name) return name:match('^[A-Za-z_][A-Za-z_0-9]*$')~=nil end
local function integer(text,width,signed)
    local value,negative=int.parse(text)
    if not int.fits(value,negative,width,signed or false) then error(text..' does not fit '..(signed and 'i' or 'u')..width,0) end
    return value
end
local function small(text,width,signed)
    local value=integer(text,width,signed)
    return tonumber(signed and int.i(value) or value)
end
function M.opcodes()
    if cached then return cached end
    local ok,json,err=util.capture({util.runtime,'opcodes'})
    if not ok then error(err,0) end
    cached={}
    for object in json:gmatch('{[^}]+}') do
        local name=object:match('"name"%s*:%s*"([A-Z_0-9]+)"')
        local opcode=tonumber(object:match('"opcode"%s*:%s*(%d+)'))
        local length=tonumber(object:match('"length"%s*:%s*(%d+)'))
        local kind=tonumber(object:match('"kind"%s*:%s*(%d+)'))
        if not name or not opcode or not length or not kind then error('invalid opcode metadata',0) end
        cached[name]={opcode=opcode,length=length,kind=kind}
    end
    return cached
end
function M.assemble(source)
    local ops=M.opcodes()
    local chunks,pc,functions,names,labels,exports,fixes={},{},{},{},{},{},{}
    local line_to_offset,offset_to_line={},{}
    pc=0
    local current, memory, callable, foreign, dynamic, pending_kind
    local signatures,sites,relocs,externs,extern_names={},{},{},{},{}
    local descriptors,descriptor_names,constants,constant_names,gc_roots={},{},{},{},{}
    local data,rodata,annotations={},{},{}
    local image_bytes=0
    local function kinds(text,count)
        if text=='-' then text='' end
        if #text~=count or text:find(dynamic and '[^iafd]' or '[^iaf]') then error('kind string must have one i/a/f'..(dynamic and '/d' or '')..' per cell (use - for zero cells)',0) end
        return (text:gsub('.',function(c) return string.char(c=='a' and 1 or c=='f' and 2 or c=='d' and 3 or 0) end))
    end
    local function emit(text) chunks[#chunks+1]=text; pc=pc+#text end
    local line_number=0
    for raw in (source..'\n'):gmatch('(.-)\n') do
        line_number=line_number+1
        local line_start=pc
        local ok,err=pcall(function()
            local line=raw:gsub(';.*$',''):match('^%s*(.-)%s*$')
            if line=='' then return end
            local tokens={} for token in line:gsub(',',' '):gmatch('%S+') do tokens[#tokens+1]=token end
            if tokens[1]=='.profile' then
                if memory or current or #tokens~=2 or (tokens[2]~='memory' and tokens[2]~='callables' and tokens[2]~='foreign' and tokens[2]~='dynamic') then error('use .profile memory|callables|foreign|dynamic before functions',0) end
                memory=true; callable=tokens[2]~='memory'; foreign=tokens[2]=='foreign' or tokens[2]=='dynamic';dynamic=tokens[2]=='dynamic'; return
            elseif tokens[1]=='.descriptor' then
                if not dynamic or not identifier(tokens[3] or '') or descriptor_names[tokens[3]] then error('invalid or duplicate dynamic descriptor',0) end
                local payload,tag;if tokens[2]=='primitive' and #tokens==4 then local codes={unit=0,bool=1,u8=2,u16=3,u32=4,u64=5,i32=6,i64=7,f64=8,string=9,any=10,word=11};local code=codes[tokens[4]];if code==nil then error('unknown primitive descriptor',0) end;tag=0;payload=string.char(code)
                elseif tokens[2]=='signature' and #tokens>=5 then local nr,nv=small(tokens[4],8),small(tokens[5],8);if #tokens~=5+nr+nv then error('signature descriptor component count mismatch',0) end;local parts={string.char(nr,nv)};for i=1,nr+nv do local d=descriptor_names[tokens[5+i]];if d==nil then error('signature component descriptor must be declared first',0) end;parts[#parts+1]=int.pack(d,4)end;tag=3;payload=table.concat(parts)
                elseif (tokens[2]=='pointer' or tokens[2]=='slice') and #tokens==5 then local owners={raw=0,strict=1,managed=2};local owner,target=owners[tokens[4]],descriptor_names[tokens[5]];if owner==nil or target==nil then error('use .descriptor pointer|slice name raw|strict|managed target',0) end;tag=tokens[2]=='pointer' and 1 or 2;payload=string.char(owner,0,0,0)..int.pack(target,4)
                elseif tokens[2]=='record' and #tokens>=6 then local size,n=small(tokens[4],32),small(tokens[5],32);if #tokens~=5+4*n then error('record descriptor field count mismatch',0) end;local parts={int.pack(size,4),int.pack(n,4)};for i=0,n-1 do local at=6+4*i;local child=descriptor_names[tokens[at+3]];if child==nil then error('record field descriptor must be declared first',0) end;parts[#parts+1]=int.pack(small(tokens[at],32),4)..int.pack(small(tokens[at+1],32),4)..int.pack(small(tokens[at+2],32),4)..int.pack(child,4)end;tag=4;payload=table.concat(parts)
                elseif tokens[2]=='array' and #tokens==6 then local child=descriptor_names[tokens[6]];if child==nil then error('use .descriptor array name size count element',0) end;tag=5;payload=int.pack(small(tokens[4],32),4)..int.pack(small(tokens[5],32),4)..int.pack(child,4)
                elseif tokens[2]=='sum' and #tokens>=8 then local size,disc,width,n=small(tokens[4],32),small(tokens[5],32),small(tokens[6],8),small(tokens[7],8);if #tokens~=7+3*n then error('sum descriptor case count mismatch',0) end;local parts={int.pack(size,4),int.pack(disc,4),string.char(width,n,0,0)};for i=0,n-1 do local at=8+3*i;local child=descriptor_names[tokens[at+2]];if child==nil then error('sum payload descriptor must be declared first',0) end;parts[#parts+1]=int.pack(integer(tokens[at],64),8)..int.pack(small(tokens[at+1],32),4)..int.pack(child,4)end;tag=6;payload=table.concat(parts)
                elseif tokens[2]=='closure' and #tokens==5 then local sig,record=descriptor_names[tokens[4]],descriptor_names[tokens[5]];if sig==nil or record==nil then error('closure descriptors must be declared first',0) end;tag=7;payload=int.pack(sig,4)..int.pack(record,4)
                else error('invalid primitive, pointer, slice, signature, record, array, sum, or closure descriptor',0) end
                descriptor_names[tokens[3]]=#descriptors;descriptors[#descriptors+1]=string.char(tag,0)..int.pack(#payload,2)..payload;return
            elseif tokens[1]=='.constant' then
                if not dynamic or (#tokens~=4 and #tokens~=5) or not identifier(tokens[2]) or constant_names[tokens[2]] then error('use .constant name kind hex [literal]',0) end
                local codes={unit=0,bool=1,u8=2,u16=3,u32=4,u64=5,i32=6,i64=7,f64=8,string=9};local code=codes[tokens[3]];if code==nil then error('unknown dynamic constant kind',0) end;local hex=tokens[4]=='-' and '' or tokens[4];if #hex%2~=0 or hex:find('[^0-9a-fA-F]') then error('constant payload must be hexadecimal bytes',0) end;local payload=hex:gsub('..',function(s)return string.char(tonumber(s,16))end);local flags=tokens[5]=='literal' and 1 or 0;constant_names[tokens[2]]=#constants;constants[#constants+1]=string.char(code,flags)..int.pack(#payload,2)..payload;return
            elseif tokens[1]=='.gcroot' then
                if not dynamic or #tokens~=3 or descriptor_names[tokens[3]]==nil then error('use .gcroot writable_offset descriptor',0) end;gc_roots[#gc_roots+1]={small(tokens[2],32),descriptor_names[tokens[3]]};return
            elseif tokens[1]=='.extern' then
                if not foreign or #tokens~=4 or not identifier(tokens[2]) or extern_names[tokens[2]] then error('use .extern name argument_kinds result_kind in foreign profile',0) end
                local ak=tokens[3]=='-' and '' or tokens[3]; local rk=tokens[4]=='-' and '' or tokens[4]
                if #ak>10 or ak:find('[^iaf]') or #rk>1 or rk:find('[^iaf]') then error('extern limit is six integer/address, four float arguments, and zero or one result',0) end
                local ni,nf=select(2,ak:gsub('[ia]','')),select(2,ak:gsub('f','')); if ni>6 or nf>4 then error('extern limit is six integer/address and four float arguments',0) end
                local ext={name=tokens[2],args=#ak,results=#rk,arg_kinds=kinds(ak,#ak),result_kinds=kinds(rk,#rk)}; extern_names[tokens[2]]=#externs; externs[#externs+1]=ext; return
            elseif tokens[1]=='.codeaddr' then
                if not callable or #tokens~=3 or not identifier(tokens[3]) then error('use .codeaddr writable_offset function in callable profile',0) end
                relocs[#relocs+1]={offset=small(tokens[2],32),name=tokens[3]}; return
            elseif tokens[1]=='.signature' then
                if not callable or (#tokens~=4 and #tokens~=6 and #tokens~=7) or not identifier(tokens[2]) or signatures[tokens[2]] then error('invalid/duplicate .signature name args results [kinds kinds [hidden_bytes]]',0) end
                local a,r=small(tokens[3],8),small(tokens[4],8)
                signatures[tokens[2]]={args=a,results=r,hidden=tokens[7] and small(tokens[7],32) or 0,
                    arg_kinds=kinds(tokens[5] or string.rep('i',a),a),result_kinds=kinds(tokens[6] or string.rep('i',r),r)}; return
            elseif tokens[1]=='.data' or tokens[1]=='.rodata' or tokens[1]=='.datazero' then
                if not memory or #tokens~=2 then error('image directives require .profile memory and one operand',0) end
                local bytes
                if tokens[1]=='.datazero' then
                    local n=small(tokens[2],32); if n>16*1024*1024-image_bytes then error('image exceeds 16 MiB',0) end
                    bytes=string.rep('\0',n)
                else
                    local hex=tokens[2]; if hex=='-' then hex='' end
                    if #hex%2~=0 or hex:find('[^0-9a-fA-F]') then error('image bytes must be pairs of hexadecimal digits',0) end
                    bytes=hex:gsub('..',function(s) return string.char(tonumber(s,16)) end)
                end
                image_bytes=image_bytes+#bytes; if image_bytes>16*1024*1024 then error('image exceeds 16 MiB',0) end
                local dst=tokens[1]=='.rodata' and rodata or data; dst[#dst+1]=bytes; return
            elseif tokens[1]=='.loadkind' then
                if not memory or pending_kind~=nil or #tokens~=2 or (tokens[2]~='int' and tokens[2]~='addr' and tokens[2]~='float' and not(dynamic and tokens[2]=='any')) then error('use .loadkind int|addr|float'..(dynamic and '|any' or '')..' before a 64-bit memory load',0) end
                pending_kind=tokens[2]=='addr' and 1 or tokens[2]=='float' and 2 or tokens[2]=='any' and 3 or 0; return
            elseif tokens[1]=='.function' then
                if pending_kind~=nil then error('load kind annotation needs a following instruction',0) end
                if (#tokens~=4 and not (memory and (#tokens==6 or #tokens==7))) or not identifier(tokens[2]) then error('use .function name argument_cells result_cells [argument_kinds result_kinds [hidden_bytes]]',0) end
                if names[tokens[2]] then error('duplicate function '..tokens[2],0) end
                current=#functions+1; names[tokens[2]]=current; labels[current]={}
                local a,r=small(tokens[3],8),small(tokens[4],8)
                functions[current]={name=tokens[2],entry=pc,args=a,results=r,hidden=tokens[7] and small(tokens[7],32) or 0,
                    arg_kinds=kinds(tokens[5] or string.rep('i',a),a),result_kinds=kinds(tokens[6] or string.rep('i',r),r)}
                return
            elseif tokens[1]=='.export' then
                if (#tokens~=2 and #tokens~=3) or not identifier(tokens[2]) then error('use .export public_name [function_name]',0) end
                exports[#exports+1]={tokens[2],tokens[#tokens],line_number}; return
            end
            if not current then error('an instruction needs a .function declaration',0) end
            if line:find(':',1,true) then
                local label,rest=line:match('^(.-):(.*)$')
                if not identifier(label) or labels[current][label] then error('invalid or duplicate label',0) end
                labels[current][label]=pc; tokens={}
                for token in rest:gsub(',',' '):gmatch('%S+') do tokens[#tokens+1]=token end
                if #tokens==0 then return end
            end
            local name=tokens[1]:upper():gsub('%.','_')
            local args=util.slice(tokens,2)
            if name=='PUSH_A' or name=='PUSH_B' then
                if #args~=1 then error('PUSH needs one integer',0) end
                local value=int.parse(args[1]); local signed=int.i(value)
                local width=(signed>=-128 and signed<=127) and 8 or (signed>=-2147483648 and signed<=2147483647) and 32 or 64
                name='PUSH'..width..'_'..name:sub(-1); args={int.format(value,true)}
            elseif name=='CGET_A' or name=='CGET_B' or name=='CSET_A' or name=='CSET_B' then
                if #args~=1 then error('context access needs a depth',0) end
                local depth=small(args[1],8); local get=name:sub(1,4)=='CGET'
                local root=get and 'CGET' or 'CSET'
                if depth<=(get and 1 or 0) then name=root..depth..'_'..name:sub(-1); args={}
                else name=root..'N_'..name:sub(-1) end
            end
            local ext=ext_by_name[name]
            if ext then
                if not dynamic then error('dynamic instruction requires .profile dynamic',0) end
                local start=pc;emit(string.char(assert(ops.EXT).opcode,ext.selector))
                if ext.family=='descriptor' or ext.family=='word-new' then if #args~=1 or descriptor_names[args[1]]==nil then error(name..' requires a descriptor name',0) end;emit(int.pack(descriptor_names[args[1]],4))
                elseif ext.family=='literal' then if #args~=2 or constant_names[args[1]]==nil then error(name..' requires a constant name and order bit',0) end;emit(int.pack(constant_names[args[1]],4));emit(int.pack(integer(args[2],8),1))
                elseif ext.family=='call' or ext.family=='tailcall' then if #args~=3 or (args[3]~='adjust' and args[3]~='exact') then error(name..' requires arguments results adjust|exact',0) end;emit(int.pack(integer(args[1],8),1)..int.pack(integer(args[2],8),1)..string.char(args[3]=='adjust' and 1 or 0)..string.rep('\0',4))
                elseif ext.family=='callable' or ext.family=='closure' then if #args~=2 or descriptor_names[args[2]]==nil then error(name..' requires function and descriptor names',0) end;fixes[#fixes+1]={site=pc,finish=0,width=4,target=args[1],owner=current,kind='absolute-function',line=line_number};emit(string.rep('\0',4)..int.pack(descriptor_names[args[2]],4))
                elseif #args~=0 then error(name..' expects no operands',0) end
                if pc~=start+ext.length then error('internal dynamic instruction length mismatch',0) end;return
            end
            if name=='CALL' then name='CALL_A' end
            if name:sub(-2)=='_A' and ops[name:sub(1,-3)] and ops[name:sub(1,-3)].kind==8 then name=name:sub(1,-3) end
            local op=ops[name]; if not op then error('unknown or unsupported instruction '..name,0) end
            local kind,length=op.kind,op.length; if kind==17 then length=3+4*#args end
            if kind==11 and not memory then error('memory instruction requires .profile memory',0) end
            if pending_kind~=nil then annotations[#annotations+1]=int.pack(pc,4)..string.char(pending_kind); pending_kind=nil end
            if (kind==12 or kind==13) and not callable then error('indirect instruction requires .profile callables',0) end
            local expected=kind==17 and #args or (name=='CGETR_A' or name=='CGETR_B') and 2 or (kind==1 or kind==16) and 1 or (kind==2 or kind==3 or kind==8 or kind==12) and 2 or (kind==9 or kind==13) and 3 or length==1 and 0 or 1
            if #args~=expected then error(name..' expects '..expected..' operands',0) end
            local start=pc; emit(string.char(op.opcode))
            if kind==17 then
                emit(int.pack(#args,2)); for _,target in ipairs(args) do fixes[#fixes+1]={site=pc,finish=start+length,width=4,target=target,owner=current,kind=kind,line=line_number};emit(string.rep('\0',4)) end
            elseif kind==16 then
                fixes[#fixes+1]={site=pc,finish=start+length,width=4,target=args[1],owner=current,kind=kind,line=line_number};emit(string.rep('\0',4))
            elseif kind==1 or kind==2 or kind==8 or kind==9 then
                local target=kind==8 and args[2] or args[1]
                if kind==8 then emit(int.pack(integer(args[1],8,true),1)) end
                local width=(kind==2 or kind==9) and 4 or 2
                fixes[#fixes+1]={site=pc,finish=start+length,width=width,target=target,owner=current,kind=kind,line=line_number}
                emit(string.rep('\0',width))
                if kind==2 or kind==9 then for i=2,#args do emit(int.pack(integer(args[i],8),1)) end end
            elseif kind==12 or kind==13 then
                local n=kind==13 and 2 or 1; for i=1,n do emit(int.pack(integer(args[i],8),1)) end
                emit(string.rep('\0',4)); sites[#sites+1]={offset=start,name=args[n+1]}
            elseif kind==11 then if length>1 then emit(int.pack(integer(args[1],(length-1)*8),length-1)) end
            elseif kind==15 then local index=extern_names[args[1]]; if index==nil then error('unknown extern '..tostring(args[1]),0) end; emit(int.pack(index,2))
            elseif kind==3 then for _,arg_ in ipairs(args) do emit(int.pack(integer(arg_,8),1)) end
            elseif name=='CGETR_A' or name=='CGETR_B' then emit(int.pack(integer(args[1],8),1)); emit(int.pack(integer(args[2],8),1))
            elseif length==2 then emit(int.pack(integer(args[1],8,kind==6 or name:match('^PUSH8_')~=nil),1))
            elseif length==5 then emit(int.pack(integer(args[1],32,true),4))
            elseif length==9 then emit(int.pack(int.parse(args[1]),8)) end
            if pc~=start+length then error('internal assembler length mismatch',0) end
        end)
        if not ok then error('line '..line_number..': '..tostring(err),0) end
        if pc>line_start then
            line_to_offset[line_number]=line_start
            for offset=line_start,pc-1 do offset_to_line[offset]=line_number end
        end
    end
    if pending_kind~=nil then error('load kind annotation needs a following instruction',0) end
    local code=table.concat(chunks)
    for _,fix in ipairs(fixes) do
        local call=fix.kind==2 or fix.kind==9
        local call=fix.kind==2 or fix.kind==9
        local absolute=fix.kind=='absolute-function'
        local address=(call or absolute) and names[fix.target] and functions[names[fix.target]].entry or not call and not absolute and labels[fix.owner][fix.target]
        if address==nil or address==false then error('line '..fix.line..': unknown '..((call or absolute) and 'function ' or 'label ')..fix.target,0) end
        local delta=absolute and (names[fix.target]-1) or address-fix.finish; local range=absolute and 2^(fix.width*8) or 2^(fix.width*8-1)
        if delta < (absolute and 0 or -range) or delta >= range then error('line '..fix.line..': branch displacement out of range',0) end
        code=code:sub(1,fix.site)..int.pack(delta,fix.width)..code:sub(fix.site+fix.width+1)
    end
    if #exports==0 and names.main then exports={{'main','main',0}} end
    local function_section={int.pack(#functions,4)}
    for _,f in ipairs(functions) do
        for _,v in ipairs({f.entry,f.args,f.results,f.hidden}) do function_section[#function_section+1]=int.pack(v,4) end
        if memory then function_section[#function_section+1]=f.arg_kinds..f.result_kinds end
    end
    local export_section={int.pack(#exports,4)}
    for _,e in ipairs(exports) do
        if not names[e[2]] then error('line '..e[3]..': unknown exported function '..e[2],0) end
        if #e[1]>255 then error('line '..e[3]..': export name exceeds 255 bytes',0) end
        export_section[#export_section+1]=int.pack(names[e[2]]-1,4)..int.pack(#e[1],2)..e[1]
    end
    local profile=dynamic and 5 or foreign and 4 or callable and 3 or memory and 2 or 1
    local section_count=dynamic and 12 or foreign and 9 or callable and 8 or memory and 6 or 3
    local header='ABC2'..int.pack(profile,2)..string.char(8,profile)..int.pack(section_count,4)..int.pack(0,4)
    local sections={table.concat(function_section),code,table.concat(export_section)}
    if memory then sections[4]=table.concat(data); sections[5]=table.concat(rodata); sections[6]=int.pack(#annotations,4)..table.concat(annotations) end
    if callable then
        local entries={int.pack(#sites,4)}
        for _,site in ipairs(sites) do
            local s=signatures[site.name] or (names[site.name] and functions[names[site.name]])
            if not s then error('unknown indirect signature '..site.name,0) end
            for _,v in ipairs({site.offset,s.args,s.results,s.hidden}) do entries[#entries+1]=int.pack(v,4) end
            entries[#entries+1]=s.arg_kinds..s.result_kinds
        end
        sections[7]=table.concat(entries); entries={int.pack(#relocs,4)}
        table.sort(relocs,function(a,b) return a.offset<b.offset end)
        for _,r in ipairs(relocs) do if not names[r.name] then error('unknown relocated function '..r.name,0) end; entries[#entries+1]=int.pack(r.offset,4)..int.pack(names[r.name]-1,4) end
        sections[8]=table.concat(entries)
    end
    if foreign then
        local entries={int.pack(#externs,4)}
        for _,ext in ipairs(externs) do entries[#entries+1]=string.char(ext.args,ext.results)..int.pack(#ext.name,2)..ext.arg_kinds..ext.result_kinds..ext.name end
        sections[9]=table.concat(entries)
    end
    if dynamic then
        sections[10]=int.pack(#descriptors,4)..table.concat(descriptors)
        sections[11]=int.pack(#constants,4)..table.concat(constants)
        table.sort(gc_roots,function(a,b)return a[1]<b[1]end);local roots={int.pack(#gc_roots,4)};for _,root in ipairs(gc_roots)do roots[#roots+1]=int.pack(root[1],4)..int.pack(root[2],4)end;sections[12]=table.concat(roots)
    end
    for tag,payload in ipairs(sections) do header=header..int.pack(tag,4)..int.pack(#payload,4)..payload end
    return header, {lineToOffset=line_to_offset, offsetToLine=offset_to_line}
end
return M

