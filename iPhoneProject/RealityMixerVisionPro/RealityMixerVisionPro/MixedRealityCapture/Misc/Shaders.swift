//
//  Shaders.swift
//  RealityMixer
//
//  Created by Fabio de Albuquerque Dela Antonio on 11/20/20.
//

import Foundation

struct Shaders {

    static let debugShader = """
    #pragma body

    vec3 color = texture2D(u_diffuseTexture, _surface.diffuseTexcoord).rgb;
    _surface.diffuse = vec4(color.r, color.g, color.b, 1.0);
    _surface.transparent = vec4(0.0, 0.0, 0.0, 1.0);
    """

    static let foregroundSurface = """
    #pragma body

    vec2 foregroundCoords = vec2(_surface.diffuseTexcoord.x * 0.5, _surface.diffuseTexcoord.y * 0.5);

    vec3 color = texture2D(u_diffuseTexture, foregroundCoords).rgb;

    _surface.diffuse = vec4(color.r, color.g, color.b, 1.0);

    vec2 alphaCoords = vec2(foregroundCoords.x, foregroundCoords.y + 0.5);

    float alpha = texture2D(u_diffuseTexture, alphaCoords).r;

    // Threshold to prevent glitches because of the video compression.
    float threshold = 0.25;
    float correctedAlpha = step(threshold, alpha) * alpha;

    float value = (1.0 - correctedAlpha);
    _surface.transparent = vec4(value, value, value, 1.0);
    """

    static let backgroundSurface = """

    #pragma body

    vec2 backgroundCoords = vec2((_surface.diffuseTexcoord.x * 0.5) + 0.5, _surface.diffuseTexcoord.y * 0.5);

    vec3 color = texture2D(u_diffuseTexture, backgroundCoords).rgb;

    _surface.diffuse = vec4(color.r, color.g, color.b, 1.0);

    vec2 alphaCoords = vec2(backgroundCoords.x, backgroundCoords.y + 0.5);

    float alpha = texture2D(u_diffuseTexture, alphaCoords).r;

    // Threshold to prevent glitches because of the video compression.
    float threshold = 0.25;
    float correctedAlpha = step(threshold, alpha) * alpha;

    float value = (1.0 - correctedAlpha);
    _surface.transparent = vec4(value, value, value, 1.0);
    """
}
