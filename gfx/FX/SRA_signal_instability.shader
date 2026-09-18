Includes = {
	"constants.fxh"
	"buttonstate.fxh"
	"sprite_animation.fxh"
	"standardfuncsgfx.fxh"
	"text.fxh"
	"utils.fxh"
}

PixelShader = {
	Samplers = {
		MapTexture = {
			Index = 0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			AddressU = "Clamp"
			AddressV = "Clamp"
		}
	}
}

VertexStruct VS_OUTPUT
{
	float4 vPosition : PDX_POSITION;
	float2 vTexCoord : TEXCOORD0;
#ifdef ANIMATED
	float4 vAnimatedTexCoord : TEXCOORD1;
#endif
};

VertexShader = {
	MainCode VertexShader
		ConstantBuffers = { Common, SpriteAnimation }
	[[
		VS_OUTPUT main(const VS_INPUT v)
		{
			VS_OUTPUT Out;
			Out.vPosition = mul(WorldViewProjectionMatrix, float4(v.vPosition.xyz, 1));
			Out.vTexCoord = v.vTexCoord;
			Out.vTexCoord += Offset;
		#ifdef ANIMATED
			Out.vAnimatedTexCoord = GetAnimatedTexcoord(v.vTexCoord);
		#endif
			return Out;
		}
	]]

	MainCode VertexShaderText
		ConstantBuffers = { TextVertex }
	[[
		VS_DEFAULT_TEXT_OUTPUT main(VS_DEFAULT_TEXT_INPUT v)
		{
			return DefaultTextVertexShader(v);
		}
	]]
}

PixelShader = {
	MainCode PixelShaderUp
		ConstantBuffers = { Common, SpriteAnimation }
	[[
		float SRA_signal_hash(float n)
		{
			return frac(sin(n) * 43758.5453123);
		}

		float SRA_signal_hash2(float2 p)
		{
			return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
		}

		float SRA_signal_noise(float2 p)
		{
			float2 i = floor(p);
			float2 f = frac(p);
			f = f * f * (3.0 - 2.0 * f);
			float a = SRA_signal_hash2(i);
			float b = SRA_signal_hash2(i + float2(1.0, 0.0));
			float c = SRA_signal_hash2(i + float2(0.0, 1.0));
			float d = SRA_signal_hash2(i + float2(1.0, 1.0));
			return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
		}

		float SRA_signal_vertical_block(float x, float center, float half_width, float softness)
		{
			float d = abs(x - center);
			return 1.0 - smoothstep(half_width, half_width + softness, d);
		}

		float4 main(VS_OUTPUT v) : PDX_COLOR
		{
			float2 uv = v.vTexCoord;
			float time = Time;

			float4 baseColor = tex2D(MapTexture, uv);
			float originalAlpha = baseColor.a * Color.a;

			// BC3 portraits can keep colored pixels in fully transparent padding.
			// Use the original, undisplaced alpha as a hard coverage mask so displaced
			// samples never draw outside the real sprite silhouette.
			if (originalAlpha <= 0.02)
			{
				return float4(0.0, 0.0, 0.0, 0.0);
			}

			float opaqueMask = smoothstep(0.02, 0.20, originalAlpha);

			// Same glitch idea as CeleTbR_3D_celestial_NO_DATA: horizontal tearing is
			// gated by time and by each Y band, then applied only to texture sampling.
			float row = floor(uv.y * 42.0);
			float glitchTrigger = SRA_signal_noise(float2(time * 10.0, uv.y * 2.0));
			float gate = step(0.43, glitchTrigger);
			float tearOffset = (SRA_signal_hash(uv.y * 31.0 + floor(time * 18.0)) - 0.5) * 0.13 * gate;

			// Long vertical rectangular light bands.
			float slowTick = floor(time * 4.0);
			float seedA = SRA_signal_hash2(float2(row + 3.0, slowTick + 1.0));
			float seedB = SRA_signal_hash2(float2(row + 19.0, slowTick + 7.0));
			float seedC = SRA_signal_hash2(float2(row + 41.0, slowTick + 13.0));

			float centerA = frac(0.12 + time * 0.10 + seedA * 0.37);
			float centerB = frac(0.72 - time * 0.07 + seedB * 0.29);
			float centerC = frac(0.39 + time * 0.04 + seedC * 0.43);

			float blockA = SRA_signal_vertical_block(uv.x, centerA, 0.030 + seedA * 0.040, 0.018);
			float blockB = SRA_signal_vertical_block(uv.x, centerB, 0.045 + seedB * 0.045, 0.024);
			float blockC = SRA_signal_vertical_block(uv.x, centerC, 0.020 + seedC * 0.030, 0.016);
			float blockMask = saturate(max(max(blockA, blockB), blockC));

			float flicker = 0.25 + 0.75 * smoothstep(0.18, 0.92, SRA_signal_hash2(float2(row, floor(time * 28.0))));
			float pulse = 0.70 + 0.30 * sin(time * 72.0 + row * 2.31);
			float instability = blockMask * flicker * pulse;

			float wave = sin(uv.y * 52.0 + time * 8.0) * 0.006;
			float offset = tearOffset + wave + (SRA_signal_hash(row + floor(time * 24.0)) - 0.5) * 0.055 * instability;
			float2 shiftedUV = float2(clamp(uv.x + offset, 0.001, 0.999), uv.y);

			float4 shiftedColor = tex2D(MapTexture, shiftedUV);
			float3 rgb = lerp(baseColor.rgb, shiftedColor.rgb, saturate((gate * 0.70 + instability) * 0.95));

			float3 signalTint = float3(0.30, 0.92, 1.00);
			rgb = lerp(rgb, signalTint, instability * 0.50);
			rgb += signalTint * instability * 0.35;

			float scanline = sin(uv.y * 180.0 + time * 10.0) * 0.5 + 0.5;
			rgb *= 1.0 - scanline * 0.14;
			rgb += signalTint * step(0.90, scanline) * blockMask * flicker * 0.10;
			rgb += SRA_signal_hash2(uv * 240.0 + time) * 0.035;

			float4 outColor = float4(rgb, originalAlpha) * float4(Color.rgb, 1.0);
			outColor.rgb *= opaqueMask;
			outColor.a = originalAlpha;
			return outColor;
		}
	]]

	MainCode PixelShaderDisable
		ConstantBuffers = { Common, SpriteAnimation }
	[[
		float4 main(VS_OUTPUT v) : PDX_COLOR
		{
			// effectButtonType can keep rendering the Disable effect when its
			// scripted potential is not met. For this portrait-only signal overlay,
			// disabled must mean invisible, not greyscaled original texture.
			return float4(0.0, 0.0, 0.0, 0.0);
		}
	]]

	MainCode PixelShaderText
		ConstantBuffers = { TextPixel }
	[[
		float4 main(VS_DEFAULT_TEXT_OUTPUT v) : PDX_COLOR
		{
			float4 OutColor = DefaultTextPixelShader(v, MapTexture);
		#ifdef DISABLED
			OutColor.rgb = GreyOutLuminosity(OutColor.rgb, GREY_OUT_GREYNESS, GREY_OUT_BRIGHTNESS);
		#endif
			return OutColor;
		}
	]]
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"
}

Effect Up
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderUp"
}

Effect Down
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderUp"
}

Effect Over
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderUp"
}

Effect Disable
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderDisable"
}

Effect TextUp
{
	VertexShader = "VertexShaderText"
	PixelShader = "PixelShaderText"
}

Effect TextDown
{
	VertexShader = "VertexShaderText"
	PixelShader = "PixelShaderText"
}

Effect TextDisable
{
	VertexShader = "VertexShaderText"
	PixelShader = "PixelShaderText"
	Defines = { "DISABLED" }
}

Effect TextOver
{
	VertexShader = "VertexShaderText"
	PixelShader = "PixelShaderText"
}

Effect SRA_signal_instability
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderUp"
}
