#define _POSIX_C_SOURCE 200809L
#include "abc.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int read_file(const char *path,void **out,size_t *size) {
    FILE *f=fopen(path,"rb");if(!f)return 0;
    if(fseek(f,0,SEEK_END)||ftell(f)<0){fclose(f);return 0;}long n=ftell(f);
    if(fseek(f,0,SEEK_SET)){fclose(f);return 0;}void *p=malloc((size_t)n?n:1);
    if(!p||fread(p,1,(size_t)n,f)!=(size_t)n||fclose(f)){free(p);return 0;}*out=p;*size=(size_t)n;return 1;
}
static int publish(const char *path,const void *bytes,size_t size) {
    size_t n=strlen(path);char *temporary=malloc(n+16);if(!temporary)return 0;
    memcpy(temporary,path,n);memcpy(temporary+n,".tmp.XXXXXX",12);int fd=mkstemp(temporary);
    if(fd<0){free(temporary);return 0;}const uint8_t *p=bytes;size_t at=0;int ok=1;
    while(at<size){ssize_t wrote=write(fd,p+at,size-at);if(wrote<=0){ok=0;break;}at+=(size_t)wrote;}
    if(ok&&fsync(fd))ok=0;if(close(fd))ok=0;
    if(ok){if(rename(temporary,path)){unlink(temporary);ok=0;}}else unlink(temporary);
    free(temporary);return ok;
}
int main(int argc,char **argv) {
    int emit_c=argc==5&&!strcmp(argv[1],"--emit-c");
    int input_index=emit_c?2:1,option_index=emit_c?3:2,output_index=emit_c?4:3;
    if((!emit_c&&argc!=4)||(emit_c&&argc!=5)||strcmp(argv[option_index],"-o")){
        fprintf(stderr,"usage: abc-opt INPUT -o OUTPUT\n       abc-opt --emit-c INPUT -o OUTPUT\n");return 2;
    }
    void *input=NULL,*output=NULL;size_t input_size=0,output_size=0;abc_error error;
    if(!read_file(argv[input_index],&input,&input_size)){fprintf(stderr,"abc-opt: cannot read %s: %s\n",argv[input_index],strerror(errno));return 1;}
    abc_status status;
    if(emit_c){char *source=NULL;status=abc_emit_c(input,input_size,&source,&output_size,&error);output=source;}
    else status=abc_optimize(input,input_size,&output,&output_size,&error);
    free(input);
    if(status!=ABC_OK){fprintf(stderr,"abc-opt: %s at byte 0x%x: %s\n",abc_status_name(status),error.offset,error.message);return 1;}
    if(!publish(argv[output_index],output,output_size)){fprintf(stderr,"abc-opt: cannot publish %s: %s\n",argv[output_index],strerror(errno));if(emit_c)abc_emitted_c_free(output);else abc_optimized_free(output);return 1;}
    if(emit_c)abc_emitted_c_free(output);else abc_optimized_free(output);return 0;
}
