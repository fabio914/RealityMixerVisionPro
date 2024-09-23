//
//  AlphaExtractor.metal
//  RealityMixerExample
//
//  Created by Fabio Dela Antonio on 23/09/2024.
//

#include <metal_stdlib>
using namespace metal;

kernel void textureProcessingKernel(
    texture2d<float, access::read> inputTexture [[ texture(0) ]],
    texture2d<float, access::write> outputTexture [[ texture(1) ]],
    uint2 gid [[ thread_position_in_grid ]]) {

    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    float4 color = inputTexture.read(gid);

    float4 alphaColor = float4(color.a, color.a, color.a, color.a);

    outputTexture.write(alphaColor, gid);
}
