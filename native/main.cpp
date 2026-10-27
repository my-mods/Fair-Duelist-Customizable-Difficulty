#define NOMINMAX
// MIT. Player-only coordinated attack tickets. No tick, scan, or settings polling.
#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <DynamicOutput/Output.hpp>
#include <Unreal/UObjectArray.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/FProperty.hpp>
#include <MinHook.h>
#include <atomic>
#include <array>
#include <algorithm>
#include <bit>
#include "TicketPolicy.hpp"
#include "TicketContract.hpp"
using namespace RC;
using namespace RC::Unreal;
static_assert(sizeof(CppUserModBase)==192,"UE4SS mod ABI changed");
namespace {
using Lua=LuaMadeSimple::Lua;
using Byte=unsigned char;
template<class T>T read(const void* p,size_t o=0){T v;std::memcpy(&v,static_cast<const Byte*>(p)+o,sizeof(v));return v;}
bool memory(void* p,size_t n,bool write=false){
 if(!TicketContract::accessible(p,n))return false;
 if(!write)return true;
 MEMORY_BASIC_INFORMATION m{};if(!VirtualQuery(p,&m,sizeof(m)))return false;
 auto protection=m.Protect&0xff;auto offset=reinterpret_cast<uintptr_t>(p)-reinterpret_cast<uintptr_t>(m.BaseAddress);
 return offset<=m.RegionSize && n<=m.RegionSize-offset && (protection==PAGE_READWRITE||protection==PAGE_WRITECOPY||protection==PAGE_EXECUTE_READWRITE||protection==PAGE_EXECUTE_WRITECOPY);
}
std::string lastError;
int logLevel=2;DWORD gameThread{};bool installed{},failed{},listening{};
std::array<uint64_t,2> tags{};
struct Identity {UObject* object{};int index=-1,serial{};};
struct Board {Identity id;size_t mapOffset{};std::array<int,2> indices{-1,-1};std::array<Tickets::Pool,2> pools{};int limit{};};
std::array<Board,4> boards{};
std::array<std::atomic_int,4> watched{};std::atomic_uint invalidated{};
void warning(const wchar_t* text){if(logLevel>=2)Output::send(STR("[FairDuelist] Attacker limit: ")+std::wstring(text)+STR("\n"));}
UObject* resolve(const Identity& id){
 if(!id.object)return nullptr;
 auto item=FUObjectArray::IndexToObject(id.index);
 return item&&item->GetUObject()==id.object&&FUObjectArray::IsValid(item,false)&&(!id.serial||item->GetSerialNumber()==id.serial)?id.object:nullptr;
}
void sync(){auto mask=invalidated.exchange(0);for(size_t i=0;i<boards.size();++i)if(mask&(1u<<i)){boards[i]={};watched[i]=-1;}}
struct Listener final:FUObjectDeleteListener {
 void NotifyUObjectDeleted(const UObjectBase*,int32_t index)override{for(size_t i=0;i<watched.size();++i)if(watched[i]==index)invalidated.fetch_or(1u<<i);}
 void OnUObjectArrayShutdown()override{invalidated=15;if(listening){FUObjectArray::RemoveUObjectDeleteListener(this);listening=false;}}
} listener;
struct Records {std::array<Byte*,2> record{};};
bool records(Board& b,Records& out,bool discover=false){
 auto object=resolve(b.id);if(!object)return false;
 auto map=reinterpret_cast<Byte*>(object)+b.mapOffset;
 if(!memory(map,0x108))return false;
 int bits=read<int>(map,0x100);if(bits<2||bits>32)return false;
 auto flags=read<Byte*>(map,0xf8);if(!flags)flags=map+0xf0;
 if(!memory(flags,4))return false;auto mask=read<uint32_t>(flags);
 auto data=read<Byte*>(map,0xe0);if(!data)data=map;
 if(!memory(data,size_t(bits)*0x70))return false;
 if(discover){
  b.indices={-1,-1};
  for(int i=0;i<bits;++i)if(mask&(1u<<i))for(int k=0;k<2;++k)if(read<uint64_t>(data,size_t(i)*0x70)==tags[k]){
   if(b.indices[k]!=-1)return false;b.indices[k]=i;
  }
 }
 for(int k=0;k<2;++k){
  int i=b.indices[k];if(i<0||i>=bits||!(mask&(1u<<i)))return false;
  auto r=data+size_t(i)*0x70;
  if(read<uint64_t>(r)!=tags[k]||!memory(r+0x10,1,true))return false;
  int held=read<int>(r,0x60);if(held<0||held>255)return false;
  auto array=read<Byte*>(r,0x58);if(!array)array=r+0x18;
  int allocated=read<int>(r,0x64);if(allocated<held||allocated>65536||(held&&!memory(array,size_t(held)*32)))return false;
  b.pools[k].held=held;out.record[k]=r;
 }
 return true;
}
void refresh(){
 if(GetCurrentThreadId()!=gameThread)return;
 sync();
 for(size_t i=0;i<boards.size();++i){auto& b=boards[i];if(!b.id.object)continue;Records rr;
  if(!records(b,rr)){boards[i]={};watched[i]=-1;warning(L"player ticket board became unavailable; waiting for the next load or Apply");continue;}
  bool owned=true;for(int k=0;k<2;++k)owned&=rr.record[k][0x10]==b.pools[k].written;
  if(!owned){
   // Restore only bytes still owned; preserve another mod's changed capacity.
   for(int k=0;k<2;++k)if(rr.record[k][0x10]==b.pools[k].written)rr.record[k][0x10]=uint8_t(std::max(int(b.pools[k].original),b.pools[k].held));
   boards[i]={};watched[i]=-1;warning(L"another change replaced a ticket capacity; this board is no longer overridden");continue;
  }
  auto wanted=Tickets::capacities(b.pools,b.limit);
  for(int k=0;k<2;++k){rr.record[k][0x10]=wanted[k];b.pools[k].written=wanted[k];}
  if(!b.limit&&wanted[0]==b.pools[0].original&&wanted[1]==b.pools[1].original){boards[i]={};watched[i]=-1;}
 }
}
using Native=uint8_t(*)(void*,const void*,void*,void*);
using Exec=void(*)(UObject*,FFrame&,void*);
Native requestOriginal{},releaseOriginal{};Exec scriptOriginal{};
uint8_t requestHook(void* c,const void* tag,void* requester,void* owner){refresh();auto r=requestOriginal(c,tag,requester,owner);refresh();return r;}
uint8_t releaseHook(void* c,const void* tag,void* requester,void* owner){refresh();auto r=releaseOriginal(c,tag,requester,owner);refresh();return r;}
void scriptHook(UObject* c,FFrame& frame,void* result){refresh();scriptOriginal(c,frame,result);refresh();}
std::array<void*,3> hooked{};
uintptr_t function(const wchar_t* path){auto fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,path);if(!fn||!fn->HasAnyFunctionFlags(FUNC_Native))throw std::runtime_error("required reflected ticket function is unavailable");return reinterpret_cast<uintptr_t>(fn->GetFuncPtr());}
size_t extent(uintptr_t fn){DWORD64 base{};auto row=RtlLookupFunctionEntry(fn,&base,nullptr);if(!row||base+row->BeginAddress!=fn)throw std::runtime_error("ticket hook is not a native function entry");return row->EndAddress-row->BeginAddress;}
uintptr_t discoverRequest(uintptr_t image){
 auto hint=image+0x5ec0c84;
 try{if(TicketContract::accessible(reinterpret_cast<void*>(hint),0x220,true)&&TicketContract::request(hint))return hint;}catch(const std::runtime_error&){}
 // A location hint is not a build gate. Re-discover after code relocation;
 // candidate bytes merely reduce decoding, semantic requirements decide support.
 auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(image);auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(image+dos->e_lfanew);auto sec=IMAGE_FIRST_SECTION(nt);uintptr_t found{};
 for(unsigned s=0;s<nt->FileHeader.NumberOfSections;++s)if(sec[s].Characteristics&IMAGE_SCN_MEM_EXECUTE){
  auto data=reinterpret_cast<Byte*>(image+sec[s].VirtualAddress);auto size=sec[s].Misc.VirtualSize;
  if(!TicketContract::accessible(data,size,true))continue;
  for(size_t i=0;i+4<size;++i)if(data[i]==0x3a && (data[i+1]&0xc0)==0x40 && data[i+2]==0x60){
   DWORD64 base{};auto row=RtlLookupFunctionEntry(reinterpret_cast<uintptr_t>(data+i),&base,nullptr);if(!row)continue;auto entry=base+row->BeginAddress;
   bool matches=false;try{matches=TicketContract::request(entry);}catch(const std::runtime_error&){continue;}
   if(matches){if(found&&found!=entry)throw std::runtime_error("ambiguous native ticket allocator");found=entry;}
  }
 }
 if(!found)throw std::runtime_error("cannot verify ticket allocator argument and capacity layout");return found;
}
void install(size_t mapOffset){
 if(installed)return;if(failed)throw std::runtime_error("ticket hooks previously failed validation");
 const auto script=function(STR("/Script/RebelAI.RebelAITicketsController:BP_RequestTicket"));
 const auto restore=function(STR("/Script/RebelAI.RebelAITicketsController:BP_RestoreTicket"));
 const auto has=function(STR("/Script/RebelAI.RebelAIBoard:HasTicketToGive"));
 auto available=TicketContract::onlyCallMatching(has,extent(has),[mapOffset](uintptr_t at){return TicketContract::availability(at,mapOffset);});
 if(!available||!TicketContract::availability(available,mapOffset))throw std::runtime_error("ticket board capacity layout cannot be verified");
 auto release=TicketContract::onlyCallMatching(restore,extent(restore),TicketContract::release);
 if(!release)throw std::runtime_error("native ticket release interface cannot be verified");
 auto request=discoverRequest(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)));
 auto status=MH_Initialize();if(status!=MH_OK&&status!=MH_ERROR_ALREADY_INITIALIZED)throw std::runtime_error("native hook initialization failed");
 std::array<void*,3> targets{reinterpret_cast<void*>(request),reinterpret_cast<void*>(release),reinterpret_cast<void*>(script)};
 std::array<void*,3> callbacks{reinterpret_cast<void*>(&requestHook),reinterpret_cast<void*>(&releaseHook),reinterpret_cast<void*>(&scriptHook)};
 std::array<void**,3> originals{reinterpret_cast<void**>(&requestOriginal),reinterpret_cast<void**>(&releaseOriginal),reinterpret_cast<void**>(&scriptOriginal)};
 try{
  for(size_t i=0;i<3;++i){if(MH_CreateHook(targets[i],callbacks[i],originals[i])!=MH_OK)throw std::runtime_error("ticket hook target unavailable or already owned");hooked[i]=targets[i];}
  for(auto h:hooked)if(MH_EnableHook(h)!=MH_OK)throw std::runtime_error("ticket hook activation failed");
 }catch(...){for(auto& h:hooked)if(h){MH_DisableHook(h);MH_RemoveHook(h);h=nullptr;}failed=true;throw;}
 installed=true;
}
bool configure(uintptr_t address,int limit,int level){
 logLevel=std::clamp(level,0,4);if(!gameThread)gameThread=GetCurrentThreadId();if(GetCurrentThreadId()!=gameThread)return false;
 sync();
 if(!address||!limit){for(auto& b:boards)b.limit=0;refresh();return true;}
 if(limit<1||limit>8)return false;
 auto object=reinterpret_cast<UObject*>(address);if(!memory(object,0x28))return false;
 int index=read<int>(object,0xc);auto item=FUObjectArray::IndexToObject(index);if(!item||item->GetUObject()!=object||!FUObjectArray::IsValid(item,false))return false;
 for(auto& b:boards)if(b.id.object==object&&resolve(b.id)){b.limit=limit;refresh();return b.id.object==object;}
 try{
  auto p=object->GetPropertyByNameInChain(STR("TicketBoard"));
  if(!p||p->GetOffset_Internal()<0||p->GetElementSize()<0x138)throw std::runtime_error("reflected TicketBoard fragment is missing or too small");
  size_t offset=size_t(p->GetOffset_Internal())+0x10;
  install(offset);
  for(int k=0;k<2;++k){FName name(k==0?STR("RebelAI.Ticket.Standard"):STR("RebelAI.Ticket.Helper"),FNAME_Find);static_assert(sizeof(name)==8);std::memcpy(&tags[k],&name,8);if(!tags[k])throw std::runtime_error("attack ticket tag is unavailable");}
  Board next;next.id={object,index,item->GetSerialNumber()};next.mapOffset=offset;next.limit=limit;Records rr;
  if(!records(next,rr,true))throw std::runtime_error("runtime Standard/Helper ticket records cannot be verified");
  for(int k=0;k<2;++k)next.pools[k].original=next.pools[k].written=rr.record[k][0x10];
  if(!listening){FUObjectArray::AddUObjectDeleteListener(&listener);listening=true;}
  for(auto& b:boards)b.limit=0;refresh();
  for(size_t i=0;i<boards.size();++i)if(!boards[i].id.object){boards[i]=next;watched[i]=index;lastError.clear();refresh();if(logLevel==4)Output::send(STR("[FairDuelist] Player attack-ticket limit applied; event-driven allocation/release hooks active\n"));return true;}
  throw std::runtime_error("prior ticket boards are still draining; retry after loading completes");
 }catch(const std::exception& e){if(logLevel>=1&&lastError!=e.what())Output::send(STR("[FairDuelist] Attacker limit unavailable: ")+std::wstring(e.what(),e.what()+std::strlen(e.what()))+STR("\n"));lastError=e.what();return false;}
}
void stop(){
 if(GetCurrentThreadId()==gameThread){for(auto& b:boards)b.limit=0;refresh();}
 for(auto& h:hooked)if(h){MH_DisableHook(h);MH_RemoveHook(h);h=nullptr;}
 if(listening){FUObjectArray::RemoveUObjectDeleteListener(&listener);listening=false;}
}
class Mod final:public CppUserModBase {
public:
 Mod(){ModName=STR("Fair Duelist - Customizable Difficulty");ModVersion=STR("1.5.1");ModAuthors=STR("my-mods");for(auto& i:watched)i=-1;}
 void on_lua_start(StringViewType name,Lua& lua,Lua&,Lua&,Lua*)override{
  if(name!=STR("FairDuelist"))return;
  lua.register_function("_FDConfigureAttackersV1",[](const Lua& l){
   // LuaMadeSimple getters remove arguments: consume index 1 each time.
   auto address=uintptr_t(l.get_integer(1));int limit=int(l.get_integer(1)),level=int(l.get_integer(1));
   l.set_bool(configure(address,limit,level));return 1;
  });
 }
 void on_lua_stop(StringViewType name,Lua&,Lua&,Lua&,Lua*)override{if(name==STR("FairDuelist")&&GetCurrentThreadId()==gameThread)configure(0,0,logLevel);}
 ~Mod()override{stop();}
};
}
extern "C" __declspec(dllexport) CppUserModBase* start_mod(){return new Mod;}
extern "C" __declspec(dllexport) void uninstall_mod(CppUserModBase* mod){delete mod;}
