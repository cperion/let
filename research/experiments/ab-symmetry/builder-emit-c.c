/* Focused public C-sink check, linked without the still-migrating ABC optimizer. */
#include "abc_tool.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    FILE *file=fopen(argv[1],"rb");if(!file)return 2;
    if(fseek(file,0,SEEK_END))return 2;
    long length=ftell(file);if(length<0||fseek(file,0,SEEK_SET))return 2;
    void *bytes=malloc((size_t)length);if(!bytes)return 2;
    if(fread(bytes,1,(size_t)length,file)!=(size_t)length)return 2;
    fclose(file);char *source=NULL;size_t size=0;abc_error error;
    abc_status status=abc_emit_c(bytes,(size_t)length,&source,&size,&error);free(bytes);
    if(status!=ABC_OK){fprintf(stderr,"%s at %u: %s\n",abc_status_name(status),error.offset,error.message);return 1;}
    int ok=fwrite(source,1,size,stdout)==size;abc_emitted_c_free(source);return ok?0:1;
}
