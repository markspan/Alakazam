function n = gpuDeviceCount()
%GPUDEVICECOUNT  Compatibility shim: reports "no GPU" when the real
%   Parallel Computing Toolbox function is unavailable.
%
%   Some third-party plugins (e.g. GEDAI) call gpuDeviceCount() directly to
%   auto-detect GPU acceleration, with no check that the toolbox providing
%   it is actually installed. On a machine without it, that call throws
%   "Unrecognized function or variable" instead of falling back to CPU.
%
%   This shim is added to the path only when the real function is missing
%   (see AutoGEDAI's ensureGpuDeviceCountShim), so it never shadows a
%   genuine GPU setup elsewhere; it simply reports zero devices, exactly
%   what a real call would report on a machine with no compatible
%   hardware, so callers take their existing CPU fallback path unchanged.
    n = 0;
end
