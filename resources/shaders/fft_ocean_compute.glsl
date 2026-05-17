#version 450

// This file is dynamically compiled by fft_water_system.gd with different #defines for each pass.

#define PI 3.14159265358979323846

layout(push_constant, std430) uniform Params {
	float frame_time;
	float delta_time;
	float gravity;
	float repeat_time;
	float depth;
	float low_cutoff;
	float high_cutoff;
	uint seed;
	uint N;
	uint length_scale_0;
	vec2 lambda;
	float foam_bias;
	float foam_decay_rate;
	float foam_add;
	float foam_threshold;
	uint length_scale_1;
	uint length_scale_2;
	uint length_scale_3;
	float pad;
} params;

struct SpectrumParameters {
	float scale;
	float angle;
	float spread_blend;
	float swell;
	float alpha;
	float peak_omega;
	float gamma;
	float short_waves_fade;
};

// Bindings
layout(set = 0, binding = 0, std430) restrict readonly buffer Spectrums {
	SpectrumParameters data[8];
} spectrums;

layout(rgba32f, set = 0, binding = 1) uniform image2DArray initial_spectrum_textures;
layout(rgba32f, set = 0, binding = 2) uniform image2DArray spectrum_textures;
layout(rgba32f, set = 0, binding = 3) uniform image2DArray displacement_textures;
layout(rg32f,   set = 0, binding = 4) uniform image2DArray slope_textures;
layout(r32f,    set = 0, binding = 5) uniform image2D buoyancy_data;
layout(rgba32f, set = 0, binding = 6) uniform image2DArray fourier_target;

// Math helpers
vec2 complex_mult(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

vec2 euler_formula(float x) {
	return vec2(cos(x), sin(x));
}

float hash(uint n) {
	n = (n << 13U) ^ n;
	n = n * (n * n * 15731U + 789221U) + 1376312589U;
	return float(n & 0x7fffffffU) / float(0x7fffffff);
}

vec2 uniform_to_gaussian(float u1, float u2) {
	float R = sqrt(-2.0 * log(max(u1, 1e-6)));
	float theta = 2.0 * PI * u2;
	return vec2(R * cos(theta), R * sin(theta));
}

float dispersion(float kMag) {
	return sqrt(params.gravity * kMag * tanh(min(kMag * params.depth, 20.0)));
}

float dispersion_derivative(float kMag) {
	float th = tanh(min(kMag * params.depth, 20.0));
	float ch = cosh(min(kMag * params.depth, 20.0));
	return params.gravity * (params.depth * kMag / (ch * ch) + th) / max(dispersion(kMag), 0.0001) / 2.0;
}

float normalization_factor(float s) {
	float s2 = s * s;
	float s3 = s2 * s;
	float s4 = s3 * s;
	if (s < 5.0) return -0.000564 * s4 + 0.00776 * s3 - 0.044 * s2 + 0.192 * s + 0.163;
	else return -4.80e-08 * s4 + 1.07e-05 * s3 - 9.53e-04 * s2 + 5.90e-02 * s + 3.93e-01;
}

float spread_power(float omega, float peak_omega) {
	if (omega > peak_omega)
		return 9.77 * pow(abs(omega / peak_omega), -2.5);
	else
		return 6.97 * pow(abs(omega / peak_omega), 5.0);
}

float cosine2s(float theta, float s) {
	return normalization_factor(s) * pow(abs(cos(0.5 * theta)), 2.0 * s);
}

float direction_spectrum(float theta, float omega, SpectrumParameters spectrum) {
	float s = spread_power(omega, spectrum.peak_omega) + 16.0 * tanh(min(omega / spectrum.peak_omega, 20.0)) * spectrum.swell * spectrum.swell;
	return mix(2.0 / PI * cos(theta) * cos(theta), cosine2s(theta - spectrum.angle, s), spectrum.spread_blend);
}

float tma_correction(float omega) {
	float omegaH = omega * sqrt(params.depth / params.gravity);
	if (omegaH <= 1.0)
		return 0.5 * omegaH * omegaH;
	if (omegaH < 2.0)
		return 1.0 - 0.5 * (2.0 - omegaH) * (2.0 - omegaH);
	return 1.0;
}

float jonswap(float omega, SpectrumParameters spectrum) {
	float sigma = (omega <= spectrum.peak_omega) ? 0.07 : 0.09;
	float r = exp(-(omega - spectrum.peak_omega) * (omega - spectrum.peak_omega) / 2.0 / sigma / sigma / spectrum.peak_omega / spectrum.peak_omega);
	
	float oneOverOmega = 1.0 / max(omega, 0.0001);
	float peakOmegaOverOmega = spectrum.peak_omega / max(omega, 0.0001);
	return spectrum.scale * tma_correction(omega) * spectrum.alpha * params.gravity * params.gravity
		* oneOverOmega * oneOverOmega * oneOverOmega * oneOverOmega * oneOverOmega
		* exp(-1.25 * peakOmegaOverOmega * peakOmegaOverOmega * peakOmegaOverOmega * peakOmegaOverOmega)
		* pow(abs(spectrum.gamma), r);
}

float short_waves_fade(float kLength, SpectrumParameters spectrum) {
	return exp(-spectrum.short_waves_fade * spectrum.short_waves_fade * kLength * kLength);
}

#ifdef PASS_INIT
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() {
	uvec3 id = gl_GlobalInvocationID;
	uint seed = id.x + params.N * id.y + params.N;
	seed += params.seed;

	float lengthScales[4] = float[](float(params.length_scale_0), float(params.length_scale_1), float(params.length_scale_2), float(params.length_scale_3));

	for (uint i = 0u; i < 4u; ++i) {
		float halfN = float(params.N) / 2.0;

		float deltaK = 2.0 * PI / lengthScales[i];
		vec2 K = (vec2(id.xy) - halfN) * deltaK;
		float kLength = length(K);

		seed += i + uint(hash(seed) * 10.0);
		vec4 uniformRandSamples = vec4(hash(seed), hash(seed * 2u), hash(seed * 3u), hash(seed * 4u));
		vec2 gauss1 = uniform_to_gaussian(uniformRandSamples.x, uniformRandSamples.y);
		vec2 gauss2 = uniform_to_gaussian(uniformRandSamples.z, uniformRandSamples.w);

		if (params.low_cutoff <= kLength && kLength <= params.high_cutoff) {
			float kAngle = atan(K.y, K.x);
			float omega = dispersion(kLength);
			float dOmegadk = dispersion_derivative(kLength);

			float spectrum = jonswap(omega, spectrums.data[i * 2u]) * direction_spectrum(kAngle, omega, spectrums.data[i * 2u]) * short_waves_fade(kLength, spectrums.data[i * 2u]);
			
			if (spectrums.data[i * 2u + 1u].scale > 0.0) {
				spectrum += jonswap(omega, spectrums.data[i * 2u + 1u]) * direction_spectrum(kAngle, omega, spectrums.data[i * 2u + 1u]) * short_waves_fade(kLength, spectrums.data[i * 2u + 1u]);
			}
			
			vec2 h0 = vec2(gauss2.x, gauss1.y) * sqrt(2.0 * spectrum * abs(dOmegadk) / max(kLength, 0.0001) * deltaK * deltaK);
			imageStore(initial_spectrum_textures, ivec3(id.xy, i), vec4(h0, 0.0, 0.0));
		} else {
			imageStore(initial_spectrum_textures, ivec3(id.xy, i), vec4(0.0));
		}
	}
}
#endif

#ifdef PASS_PACK
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() {
	uvec3 id = gl_GlobalInvocationID;
	for (uint i = 0u; i < 4u; ++i) {
		vec2 h0 = imageLoad(initial_spectrum_textures, ivec3(id.xy, i)).rg;
		uvec2 conj_id = uvec2((params.N - id.x) % params.N, (params.N - id.y) % params.N);
		vec2 h0conj = imageLoad(initial_spectrum_textures, ivec3(conj_id, i)).rg;

		imageStore(initial_spectrum_textures, ivec3(id.xy, i), vec4(h0, h0conj.x, -h0conj.y));
	}
}
#endif

#ifdef PASS_UPDATE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
void main() {
	uvec3 id = gl_GlobalInvocationID;
	float lengthScales[4] = float[](float(params.length_scale_0), float(params.length_scale_1), float(params.length_scale_2), float(params.length_scale_3));

	for (uint i = 0u; i < 4u; ++i) {
		vec4 initialSignal = imageLoad(initial_spectrum_textures, ivec3(id.xy, i));
		vec2 h0 = initialSignal.xy;
		vec2 h0conj = initialSignal.zw;

		float halfN = float(params.N) / 2.0;
		vec2 K = (vec2(id.xy) - halfN) * 2.0 * PI / lengthScales[i];
		float kMag = length(K);
		float kMagRcp = 1.0 / max(kMag, 0.0001);

		if (kMag < 0.0001) {
			kMagRcp = 1.0;
		}

		float w_0 = 2.0 * PI / params.repeat_time;
		float disp = floor(sqrt(params.gravity * kMag) / w_0) * w_0 * params.frame_time;

		vec2 exponent = euler_formula(disp);

		vec2 htilde = complex_mult(h0, exponent) + complex_mult(h0conj, vec2(exponent.x, -exponent.y));
		vec2 ih = vec2(-htilde.y, htilde.x);

		vec2 displacementX = ih * K.x * kMagRcp;
		vec2 displacementY = htilde;
		vec2 displacementZ = ih * K.y * kMagRcp;

		vec2 displacementX_dx = -htilde * K.x * K.x * kMagRcp;
		vec2 displacementY_dx = ih * K.x;
		vec2 displacementZ_dx = -htilde * K.x * K.y * kMagRcp;

		vec2 displacementY_dz = ih * K.y;
		vec2 displacementZ_dz = -htilde * K.y * K.y * kMagRcp;

		vec2 htildeDisplacementX = vec2(displacementX.x - displacementZ.y, displacementX.y + displacementZ.x);
		vec2 htildeDisplacementZ = vec2(displacementY.x - displacementZ_dx.y, displacementY.y + displacementZ_dx.x);
		
		vec2 htildeSlopeX = vec2(displacementY_dx.x - displacementY_dz.y, displacementY_dx.y + displacementY_dz.x);
		vec2 htildeSlopeZ = vec2(displacementX_dx.x - displacementZ_dz.y, displacementX_dx.y + displacementZ_dz.x);

		imageStore(spectrum_textures, ivec3(id.xy, i * 2u), vec4(htildeDisplacementX, htildeDisplacementZ));
		imageStore(spectrum_textures, ivec3(id.xy, i * 2u + 1u), vec4(htildeSlopeX, htildeSlopeZ));
	}
}
#endif

// FFT Logic
#if defined(PASS_FFT_X) || defined(PASS_FFT_Y)
#define SIZE 1024
#define LOG_SIZE 10

layout(local_size_x = SIZE, local_size_y = 1, local_size_z = 1) in;

shared vec4 fftGroupBuffer[2][SIZE];

void butterfly_values(uint step_idx, uint index, out uvec2 indices, out vec2 twiddle) {
	const float twoPi = 6.28318530718;
	uint b = SIZE >> (step_idx + 1u);
	uint w = b * (index / b);
	uint i = (w + index) % SIZE;
	twiddle = vec2(cos(-twoPi / float(SIZE) * float(w)), sin(-twoPi / float(SIZE) * float(w)));
	twiddle.y = -twiddle.y; // Inverse FFT
	indices = uvec2(i, i + b);
}

vec4 fft_calc(uint threadIndex, vec4 input_val) {
	fftGroupBuffer[0][threadIndex] = input_val;
	barrier();
	memoryBarrierShared();
	bool flag = false;

	for (uint step_idx = 0u; step_idx < LOG_SIZE; ++step_idx) {
		uvec2 inputsIndices;
		vec2 twiddle;
		butterfly_values(step_idx, threadIndex, inputsIndices, twiddle);

		vec4 v = fftGroupBuffer[int(flag)][inputsIndices.y];
		fftGroupBuffer[int(!flag)][threadIndex] = fftGroupBuffer[int(flag)][inputsIndices.x] + vec4(complex_mult(twiddle, v.xy), complex_mult(twiddle, v.zw));

		flag = !flag;
		barrier();
		memoryBarrierShared();
	}

	vec4 result = fftGroupBuffer[int(flag)][threadIndex];
	barrier();
	return result;
}

void main() {
	uvec3 id = gl_GlobalInvocationID;
#ifdef PASS_FFT_X
	for (uint i = 0u; i < 8u; ++i) {
		vec4 input_val = imageLoad(fourier_target, ivec3(id.xy, i));
		vec4 result = fft_calc(id.x, input_val);
		imageStore(fourier_target, ivec3(id.xy, i), result);
	}
#endif
#ifdef PASS_FFT_Y
	for (uint i = 0u; i < 8u; ++i) {
		vec4 input_val = imageLoad(fourier_target, ivec3(id.yx, i));
		vec4 result = fft_calc(id.x, input_val);
		imageStore(fourier_target, ivec3(id.yx, i), result);
	}
#endif
}
#endif

#ifdef PASS_ASSEMBLE
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

vec4 permute(vec4 data, vec3 id) {
	return data * (1.0 - 2.0 * float((uint(id.x) + uint(id.y)) % 2u));
}

void main() {
	uvec3 id = gl_GlobalInvocationID;
	for (uint i = 0u; i < 4u; ++i) {
		vec4 htildeDisplacement = permute(imageLoad(spectrum_textures, ivec3(id.xy, i * 2u)), vec3(id));
		vec4 htildeSlope = permute(imageLoad(spectrum_textures, ivec3(id.xy, i * 2u + 1u)), vec3(id));

		vec2 dxdz = htildeDisplacement.rg;
		vec2 dydxz = htildeDisplacement.ba;
		vec2 dyxdyz = htildeSlope.rg;
		vec2 dxxdzz = htildeSlope.ba;
		
		float jacobian = (1.0 + params.lambda.x * dxxdzz.x) * (1.0 + params.lambda.y * dxxdzz.y) - params.lambda.x * params.lambda.y * dydxz.y * dydxz.y;

		vec3 displacement = vec3(params.lambda.x * dxdz.x, dydxz.x, params.lambda.y * dxdz.y);
		vec2 slopes = dyxdyz.xy / (1.0 + abs(dxxdzz * params.lambda));

		// Read old foam, decay, and add new foam based on jacobian
		float foam = imageLoad(displacement_textures, ivec3(id.xy, i)).a;
		foam *= exp(-params.foam_decay_rate);
		foam = clamp(foam, 0.0, 1.0);

		float biasedJacobian = max(0.0, -(jacobian - params.foam_bias));

		if (biasedJacobian > params.foam_threshold) {
			foam += params.foam_add * biasedJacobian;
		}

		imageStore(displacement_textures, ivec3(id.xy, i), vec4(displacement, foam));
		imageStore(slope_textures, ivec3(id.xy, i), vec4(slopes, 0.0, 0.0));

		if (i == 0u) {
			imageStore(buoyancy_data, ivec2(id.xy), vec4(displacement.y, 0.0, 0.0, 0.0));
		}
	}
}
#endif
