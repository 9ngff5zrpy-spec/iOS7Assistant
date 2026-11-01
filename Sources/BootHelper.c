#include <libirecovery.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static void check(irecv_error_t e,const char *stage){if(e){fprintf(stderr,"%s: %s\n",stage,irecv_strerror(e));exit(1);} }
int main(int argc,char **argv){
 int probe=argc==4&&!strcmp(argv[1],"--probe")&&!strcmp(argv[2],"--ecid");
 if(!probe && (argc!=5||strcmp(argv[1],"--ecid"))){fprintf(stderr,"Usage: ios7-boot --ecid ECID DeviceTree Kernel\n");return 2;}
 const char *id=probe?argv[3]:argv[2];char *end=NULL;errno=0;unsigned long long ecid=strtoull(id,&end,0);
 if(errno||!end||*end||!ecid)return 2;
 irecv_client_t c=NULL;check(irecv_open_with_ecid(&c,ecid),"open");
 const struct irecv_device_info *info=irecv_get_device_info(c);
 if(!info||info->ecid!=ecid||info->cpid!=0x8960||info->bdid!=2){fprintf(stderr,"Unsupported device\n");irecv_close(c);return 2;}
 int mode=0;check(irecv_get_mode(c,&mode),"mode");if(mode<IRECV_K_RECOVERY_MODE_1||mode>IRECV_K_RECOVERY_MODE_4){fprintf(stderr,"Recovery required\n");irecv_close(c);return 2;}
 char *v=NULL;check(irecv_getenv(c,"build-version",&v),"version");
 if(!v||strcmp(v,"iBoot-1940.10.58")){fprintf(stderr,"Expected iBoot-1940.10.58\n");free(v);irecv_close(c);return 2;}
 if(probe){puts(v);free(v);irecv_close(c);return 0;}free(v);
 check(irecv_send_file(c,argv[3],0),"DeviceTree");check(irecv_send_command(c,"devicetree"),"devicetree");
 check(irecv_send_file(c,argv[4],0),"Kernelcache");
 /* Upstream idevicerestore intentionally ignores the status of this notification. */
 irecv_usb_control_transfer(c,0x21,1,0,0,NULL,0,5000);
 check(irecv_send_command(c,"setenv boot-args -v rd=disk0s1s1"),"boot arguments");
 check(irecv_send_command_breq(c,"bootx",1),"bootx");irecv_close(c);puts("BOOT_COMMAND_SENT");return 0;
}
