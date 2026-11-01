#include <libirecovery.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void check(irecv_error_t e,const char *s){if(e){fprintf(stderr,"%s: %s\n",s,irecv_strerror(e));exit(1);}printf("%s: OK\n",s);fflush(stdout);}
int main(int argc,char **argv){
 int probe=argc==4&&!strcmp(argv[1],"--probe")&&!strcmp(argv[2],"--ecid");
 if(!probe&&(argc!=4||strcmp(argv[1],"--ecid")))return 2;
 char *end=NULL;unsigned long long ecid=strtoull(probe?argv[3]:argv[2],&end,0);if(!end||*end||!ecid)return 2;
 char paths[3][4096];const char *names[]={"RestoreRamdisk.img4","DeviceTree.img4","Kernelcache.img4"};
 if(!probe)for(int i=0;i<3;i++){if(snprintf(paths[i],sizeof(paths[i]),"%s/%s",argv[3],names[i])>=(int)sizeof(paths[i]))return 2;FILE *f=fopen(paths[i],"rb");if(!f){perror(paths[i]);return 2;}fclose(f);}
 irecv_client_t c=NULL;check(irecv_open_with_ecid(&c,ecid),"Open target iPhone");
 const struct irecv_device_info *info=irecv_get_device_info(c);if(!info||info->ecid!=ecid||info->cpid!=0x8960||info->bdid!=2){irecv_close(c);return 2;}
 int mode=0;check(irecv_get_mode(c,&mode),"Mode");if(mode<IRECV_K_RECOVERY_MODE_1||mode>IRECV_K_RECOVERY_MODE_4){irecv_close(c);return 2;}
 char *v=NULL;check(irecv_getenv(c,"build-version",&v),"Read iBoot");if(!v||strcmp(v,"iBoot-2261.3.32")){fprintf(stderr,"Unexpected iBoot: %s\n",v?v:"none");free(v);irecv_close(c);return 2;}free(v);if(probe){irecv_close(c);puts("MAINTENANCE_RECOVERY_VERIFIED");return 0;}
 check(irecv_send_file(c,paths[0],0),"Send SSH ramdisk");check(irecv_send_command(c,"ramdisk"),"Load SSH ramdisk");
 check(irecv_send_file(c,paths[1],0),"Send DeviceTree");check(irecv_send_command(c,"devicetree"),"Load DeviceTree");
 check(irecv_send_file(c,paths[2],0),"Send kernel");
 irecv_usb_control_transfer(c,0x21,1,0,0,NULL,0,5000);
 check(irecv_send_command(c,"setenv boot-args -v rd=md0 amfi=0xff cs_enforcement_disable=1 wdt=-1"),"Set SSH boot arguments");
 check(irecv_send_command_breq(c,"bootx",1),"Start SSH ramdisk");irecv_close(c);return 0;
}
