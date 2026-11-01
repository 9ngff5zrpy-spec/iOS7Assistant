#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
int main(void) {
 // The maintenance userland contains the versioned framework without the
 // unversioned symlink found on a normal system.
 const char *libraries[]={
  "/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit",
  "/System/Library/Frameworks/IOKit.framework/IOKit"
 };
 void *kit=NULL;
 for(unsigned i=0;i<sizeof(libraries)/sizeof(libraries[0]);i++){
  kit=dlopen(libraries[i],RTLD_NOW);
  if(kit)break;
  fprintf(stderr,"IOKit load failed (%s): %s\n",libraries[i],dlerror());
 }
 if(!kit)return 1;
 uint32_t (*entry)(uint32_t,const char*)=dlsym(kit,"IORegistryEntryFromPath");
 CFTypeRef (*property)(uint32_t,CFStringRef,CFAllocatorRef,uint32_t)=dlsym(kit,"IORegistryEntryCreateCFProperty");
 int (*release)(uint32_t)=dlsym(kit,"IOObjectRelease");
 if(!entry||!property||!release){fprintf(stderr,"IOKit registry functions unavailable\n");dlclose(kit);return 1;}
 const char *paths[]={"IODeviceTree:/chosen","IODeviceTree:/"};
 for(unsigned i=0;i<2;i++){
  uint32_t node=entry(0,paths[i]);if(!node)continue;
  CFTypeRef value=property(node,CFSTR("unique-chip-id"),kCFAllocatorDefault,0);release(node);
  if(!value)continue;
  uint64_t ecid=0;
  if(CFGetTypeID(value)==CFDataGetTypeID()){
   CFIndex n=CFDataGetLength(value);const UInt8 *b=CFDataGetBytePtr(value);
   if(n>0&&n<=8)for(CFIndex j=0;j<n;j++)ecid|=(uint64_t)b[j]<<(8*j);
  } else if(CFGetTypeID(value)==CFNumberGetTypeID())CFNumberGetValue(value,kCFNumberSInt64Type,&ecid);
  CFRelease(value);
  if(ecid){printf("ECID: 0x%016llx\n",(unsigned long long)ecid);dlclose(kit);return 0;}
 }
 fprintf(stderr,"Could not read unique-chip-id\n");dlclose(kit);return 1;
}
