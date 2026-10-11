// MIT. Operation-specific Windows x64 dispatch validation; no binary identity gates.
#pragma once
#include <Windows.h>
#include <Zydis/Zydis.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <deque>
#include <vector>
#include <stdexcept>
namespace TicketContract {
inline bool accessible(const void* ptr,size_t size,bool code=false) {
    auto cursor=reinterpret_cast<uintptr_t>(ptr);
    if(!cursor || !size || size>(std::numeric_limits<uintptr_t>::max)()-cursor)return false;
    const auto end=cursor+size;
    while(cursor<end) {
        MEMORY_BASIC_INFORMATION m{};
        if(!VirtualQuery(reinterpret_cast<void*>(cursor),&m,sizeof(m)) || m.State!=MEM_COMMIT || (m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return false;
        const auto p=m.Protect&0xff;
        const bool execute=p==PAGE_EXECUTE_READ||p==PAGE_EXECUTE_READWRITE||p==PAGE_EXECUTE_WRITECOPY;
        if(!execute && (code || (p!=PAGE_READONLY&&p!=PAGE_READWRITE&&p!=PAGE_WRITECOPY)))return false;
        const auto base=reinterpret_cast<uintptr_t>(m.BaseAddress);
        if(m.RegionSize>(std::numeric_limits<uintptr_t>::max)()-base || base+m.RegionSize<=cursor)return false;
        cursor=base+m.RegionSize;
    }
    return true;
}
struct Instruction {ZydisDecodedInstruction ins{};std::array<ZydisDecodedOperand,ZYDIS_MAX_OPERAND_COUNT> op{};};
inline Instruction decode(uintptr_t address) {
    // Copy only individually verified bytes: a function need not occupy one region.
    std::array<uint8_t,ZYDIS_MAX_INSTRUCTION_LENGTH> bytes{};size_t n=0;
    for(;n<bytes.size() && address<=UINTPTR_MAX-n && accessible(reinterpret_cast<void*>(address+n),1,true);++n)
        std::memcpy(&bytes[n],reinterpret_cast<void*>(address+n),1);
    ZydisDecoder decoder{};ZydisDecoderInit(&decoder,ZYDIS_MACHINE_MODE_LONG_64,ZYDIS_STACK_WIDTH_64);
    Instruction d;
    if(!ZYAN_SUCCESS(ZydisDecoderDecodeFull(&decoder,bytes.data(),n,&d.ins,d.op.data())))throw std::runtime_error("native route instruction is unreadable or undecodable");
    return d;
}
inline int reg(ZydisRegister r) {
    r=ZydisRegisterGetLargestEnclosing(ZYDIS_MACHINE_MODE_LONG_64,r);
    if(r>=ZYDIS_REGISTER_RAX && r<=ZYDIS_REGISTER_R15)return int(r-ZYDIS_REGISTER_RAX);
    return -1;
}
inline bool highByte(ZydisRegister r){return r==ZYDIS_REGISTER_AH||r==ZYDIS_REGISTER_BH||r==ZYDIS_REGISTER_CH||r==ZYDIS_REGISTER_DH;}
inline bool nonvolatile(int r) {return r==reg(ZYDIS_REGISTER_RBX)||r==reg(ZYDIS_REGISTER_RBP)||r==reg(ZYDIS_REGISTER_RSI)||r==reg(ZYDIS_REGISTER_RDI)||r>=reg(ZYDIS_REGISTER_R12);}
inline uintptr_t relative(uintptr_t at,const Instruction& d,unsigned operand=0) {
    ZyanU64 address{};
    if(!ZYAN_SUCCESS(ZydisCalcAbsoluteAddress(&d.ins,&d.op[operand],at,&address)))throw std::runtime_error("native route target cannot be resolved");
    return uintptr_t(address);
}
}

namespace TicketContract {
struct Layout {size_t boardMap=0x530,stride=0x70,storage=0xe0,bits=0xf0,capacity=0x10,held=0x60;};
inline bool mem(const ZydisDecodedOperand& o,int64_t offset,unsigned width=0) {
 return o.type==ZYDIS_OPERAND_TYPE_MEMORY && o.mem.disp.value==offset && (!width||o.size==width);
}
struct InstructionRange {
 uintptr_t start{},end{};
 struct Iterator {uintptr_t at{},end{};
  auto operator*()const{return std::pair<uintptr_t,Instruction>{at,decode(at)};}
  Iterator& operator++(){at+=decode(at).ins.length;return *this;}
  bool operator!=(const Iterator&)const{return at<end;}
 };
 Iterator begin()const{return {start,end};}Iterator finish()const{return {end,end};}
 Iterator endIterator()const{return finish();}
};
struct Instructions {uintptr_t entry{};size_t bytes{};
 auto begin()const{return InstructionRange::Iterator{entry,entry+bytes};}
 auto end()const{return InstructionRange::Iterator{entry+bytes,entry+bytes};}
};
inline Instructions instructions(uintptr_t entry,size_t bytes){return {entry,bytes};}
inline bool interfaceArgument(uintptr_t entry,size_t bytes) {
 // The hook forwards four untouched native arguments. Only r9 is interpreted:
 // it must supply the ticket-board interface whose +0x10 slot returns its fragment.
 std::array<int,16> aliases{};aliases[reg(ZYDIS_REGISTER_R9)]=1;
 for(auto [at,d]:instructions(entry,bytes)) {
  auto a=d.op[0],b=d.op[1];auto m=d.ins.mnemonic;
  if(m==ZYDIS_MNEMONIC_CALL && mem(a,0x10,64)) {
   int base=reg(a.mem.base);
   if(base>=0 && aliases[base]==2 && aliases[reg(ZYDIS_REGISTER_RCX)]==1)return true;
  }
  int assign=0;bool has=false;
  if(m==ZYDIS_MNEMONIC_MOV && a.type==ZYDIS_OPERAND_TYPE_REGISTER && a.size==64){
   if(b.type==ZYDIS_OPERAND_TYPE_REGISTER){int i=reg(b.reg.value);assign=i>=0?aliases[i]:0;has=true;}
   if(mem(b,0,64)){int i=reg(b.mem.base);assign=i>=0&&aliases[i]==1?2:0;has=true;}
  }
  for(unsigned i=0;i<d.ins.operand_count;++i) {auto o=d.op[i];if(o.type==ZYDIS_OPERAND_TYPE_REGISTER&&(o.actions&ZYDIS_OPERAND_ACTION_MASK_WRITE)){int j=reg(o.reg.value);if(j>=0)aliases[j]=0;}}
  if(has){int j=reg(a.reg.value);if(j>=0)aliases[j]=assign;}
  if(m==ZYDIS_MNEMONIC_CALL)for(int i:{0,1,2,8,9,10,11})aliases[i]=0;
 }
 return false;
}
inline bool request(uintptr_t entry) {
 if(!interfaceArgument(entry,0x100))return false;
 bool storage=false,stride=false,capacity=false,bitset=false;
 int capReg=-1,recordReg=-1;
 for(auto [at,d]:instructions(entry,0x220)) {
  auto a=d.op[0],b=d.op[1];auto m=d.ins.mnemonic;
  storage|=m==ZYDIS_MNEMONIC_MOV&&mem(b,0xe0,64);
  stride|=m==ZYDIS_MNEMONIC_IMUL&&d.op[2].type==ZYDIS_OPERAND_TYPE_IMMEDIATE&&d.op[2].imm.value.u==0x70;
  bitset|=m==ZYDIS_MNEMONIC_LEA&&mem(b,0xf0);
  if((m==ZYDIS_MNEMONIC_MOV||m==ZYDIS_MNEMONIC_MOVZX)&&a.type==ZYDIS_OPERAND_TYPE_REGISTER&&mem(b,0x10,8)) {capReg=reg(a.reg.value);recordReg=reg(b.mem.base);capacity=true;continue;}
  if(m==ZYDIS_MNEMONIC_CMP && capacity && a.type==ZYDIS_OPERAND_TYPE_REGISTER && reg(a.reg.value)==capReg && mem(b,0x60,8) && reg(b.mem.base)==recordReg){
   auto branch=decode(at+d.ins.length);
   return storage&&stride&&bitset&&(branch.ins.mnemonic==ZYDIS_MNEMONIC_JNZ||branch.ins.mnemonic==ZYDIS_MNEMONIC_JZ);
  }
 }
 return false;
}
inline bool release(uintptr_t entry) {
 // We do not depend on the release implementation: forwarding ABI and board
 // identity are enough. Its interface access is independently anchored by the
 // reflected BP_RestoreTicket thunk's direct call when installing the hook.
 return interfaceArgument(entry,0x80);
}
inline bool availability(uintptr_t entry,size_t mapOffset) {
 bool map=false,storage=false,stride=false;int capReg=-1;
 for(auto [at,d]:instructions(entry,0xc0)) {
  auto a=d.op[0],b=d.op[1];auto m=d.ins.mnemonic;
  map|=m==ZYDIS_MNEMONIC_LEA&&mem(b,int64_t(mapOffset))&&b.mem.base==ZYDIS_REGISTER_RCX;
  storage|=m==ZYDIS_MNEMONIC_LEA&&mem(b,0xe0);
  stride|=m==ZYDIS_MNEMONIC_IMUL&&d.op[2].type==ZYDIS_OPERAND_TYPE_IMMEDIATE&&d.op[2].imm.value.u==0x70;
  if(m==ZYDIS_MNEMONIC_MOVZX&&mem(b,0x10,8))capReg=reg(a.reg.value);
  if(m==ZYDIS_MNEMONIC_CMP&&a.type==ZYDIS_OPERAND_TYPE_REGISTER&&reg(a.reg.value)==capReg&&mem(b,0x60,32))return map&&storage&&stride;
 }
 return false;
}
template<class Predicate> inline uintptr_t onlyCallMatching(uintptr_t wrapper,size_t bytes,Predicate predicate) {
 uintptr_t found{};
 for(auto [at,d]:instructions(wrapper,bytes))if(d.ins.mnemonic==ZYDIS_MNEMONIC_CALL&&d.op[0].type==ZYDIS_OPERAND_TYPE_IMMEDIATE&&d.op[0].imm.is_relative) {
  auto target=relative(at,d);
  bool matches=false;try{matches=predicate(target);}catch(const std::exception&){}
  if(matches){if(found&&found!=target)throw std::runtime_error("ambiguous ticket implementation");found=target;}
 }
 return found;
}
}
