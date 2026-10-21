shader_type canvas_item;
uniform sampler2D meeting : hint_screen_texture, filter_linear_mipmap;
void fragment(){ float opacity=COLOR.a;
vec3 world=textureLod(meeting,SCREEN_UV,1.8).rgb;
float edge=(1.0-smoothstep(0.14,0.75,distance(SCREEN_UV,vec2(0.5))));
COLOR=vec4(world*vec3(0.43,0.43,0.45)*mix(0.46,1.0,edge),opacity);
}
