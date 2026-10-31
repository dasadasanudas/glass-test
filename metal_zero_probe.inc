#import <Metal/Metal.h>
#import <math.h>
#import <stdint.h>
static int runMetalZeroProbe(void) {
 @autoreleasepool {
  id<MTLDevice> dev=MTLCreateSystemDefaultDevice(); if(!dev){puts("METAL_ZERO no device"); return 0;}
  NSString *src=@"#include <metal_stdlib>\nusing namespace metal;\nkernel void zero_probe(device const float4* in [[buffer(0)]], device uint* out [[buffer(1)]], device const float* ends [[buffer(2)]], uint id [[thread_position_in_grid]]) {\n float4 v=in[id]; half d=half(v.x), inv=half(v.y), amount=half(v.z); half raw=inv*(-d); half x=clamp(raw,half(0),half(1)); half q=x*(half(2)-x); half root=sqrt(q); half h=amount-root*amount; float width=ends[id]-v.w; float recip=1.0f/width; float bias=-v.w*recip; float ramp=clamp(fma(v.x,recip,bias),0.0f,1.0f); uint b=id*8; out[b]=as_type<ushort>(d); out[b+1]=as_type<ushort>(inv); out[b+2]=as_type<ushort>(raw); out[b+3]=as_type<ushort>(x); out[b+4]=as_type<ushort>(q); out[b+5]=as_type<ushort>(h); out[b+6]=as_type<uint>(bias); out[b+7]=as_type<uint>(ramp); }\n";
  const float input[28]={-1,INFINITY,-35.2f,0, -1e-9f,INFINITY,-35.2f,0, -0.0f,INFINITY,-35.2f,0, 0.0f,INFINITY,-35.2f,0, 1e-9f,INFINITY,-35.2f,0, 1,INFINITY,-35.2f,0, 0,1,-35.2f,-1};const float ends[7]={0,0,0,0,0,0,1};
  for(int fast=0;fast<2;fast++) {
   NSError *error=nil; MTLCompileOptions *opt=[MTLCompileOptions new];opt.fastMathEnabled=fast;
   id<MTLLibrary> lib=[dev newLibraryWithSource:src options:opt error:&error];if(!lib){printf("METAL_ZERO compile_error fast=%d %s\n",fast,error.localizedDescription.UTF8String);continue;}
   id<MTLFunction> fn=[lib newFunctionWithName:@"zero_probe"];id<MTLComputePipelineState> pipe=[dev newComputePipelineStateWithFunction:fn error:&error];if(!pipe){printf("METAL_ZERO pipeline_error fast=%d %s\n",fast,error.localizedDescription.UTF8String);continue;}
   id<MTLBuffer> inputBuffer=[dev newBufferWithBytes:input length:sizeof(input) options:MTLResourceStorageModeShared];id<MTLBuffer> endBuffer=[dev newBufferWithBytes:ends length:sizeof(ends) options:MTLResourceStorageModeShared];id<MTLBuffer> outputBuffer=[dev newBufferWithLength:7*8*sizeof(uint32_t) options:MTLResourceStorageModeShared];
   id<MTLCommandQueue> queue=[dev newCommandQueue];id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];[enc setComputePipelineState:pipe];[enc setBuffer:inputBuffer offset:0 atIndex:0];[enc setBuffer:outputBuffer offset:0 atIndex:1];[enc setBuffer:endBuffer offset:0 atIndex:2];[enc dispatchThreads:MTLSizeMake(7,1,1) threadsPerThreadgroup:MTLSizeMake(7,1,1)];[enc endEncoding];[cb commit];[cb waitUntilCompleted];
   if(cb.status!=MTLCommandBufferStatusCompleted){printf("METAL_ZERO command_error fast=%d status=%ld %s\n",fast,(long)cb.status,cb.error.localizedDescription.UTF8String?:"none");continue;}
   uint32_t *v=outputBuffer.contents;printf("METAL_ZERO device=%s fast=%d independent_endpoints=1\n",dev.name.UTF8String,fast);for(int i=0;i<7;i++)printf("METAL_ZERO_CASE fast=%d idx=%d distance=%.9g d=%04x inv=%04x raw=%04x sat=%04x q=%04x h=%04x bias=%08x ramp=%08x\n",fast,i,input[i*4],v[i*8],v[i*8+1],v[i*8+2],v[i*8+3],v[i*8+4],v[i*8+5],v[i*8+6],v[i*8+7]);
  } return 0;
 }
}
