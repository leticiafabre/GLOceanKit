ReadOverNetwork = 0;

if ReadOverNetwork == 1
    baseURL = '/Volumes/seattle_data1/cwortham/research/nsf_iwv/model_raw/';
else
    baseURL = '/Volumes/Samsung_T5/nsf_iwv/WintersNonlinear/';
end

% Version 2 files, from December 2018
NonlinearSteadyStateFile = strcat(baseURL,'EarlyV2_GM_NL_forced_damped_restart');
% LinearSteadyStateFile = strcat(baseURL,'EarlyV2_GM_LIN_unforced_damped_restart');

% ExponentialSpinup = strcat(baseURL,'EarlyV2_GMexp_NL_forced_damped_64cube');

file = NonlinearSteadyStateFile;

output_directory = '/Users/jearly/Documents/ManuscriptRepositories/garrett-munk-lateral-diffusivity/data/2019_05';
output_directory = baseURL;

[filepath,name,ext] = fileparts(file);
outputfile = fullfile(output_directory,strcat(name,'_moorings.mat'));

WM = WintersModel(file);
wavemodel = WM.wavemodel;

nFiles = WM.NumberOf3DOutputFiles;
fileIncrements = 1:1:nFiles;

x = wavemodel.x;
y = wavemodel.y;
z = wavemodel.z;
stride = 8;

nDepths = 5;
depth_start_index = ceil(length(z)/2);
depth_stride = (length(z)-depth_start_index)/(nDepths-1);
depth_indices = depth_start_index:depth_stride:length(z);
nDepths = length(depth_indices);
nT = length(fileIncrements);

t = zeros(length(fileIncrements),1);
u4d = zeros(length(x)/stride, length(y)/stride, nDepths, nT);
v4d = zeros(length(x)/stride, length(y)/stride, nDepths, nT);
w4d = zeros(length(x)/stride, length(y)/stride, nDepths, nT);
startTime = datetime('now');
for iFile = 1:length(fileIncrements)
    if mod(iFile,10) == 2
        timePerStep = (datetime('now')-startTime)/(iFile-1);
        timeRemaining = (nT-iFile+1)*timePerStep;
        fprintf('reading values time step %d of %d to file. Estimated finish time %s (%s from now)\n', iFile, nT, datestr(datetime('now')+timeRemaining), datestr(timeRemaining, 'HH:MM:SS')) ;
    end
    file = WM.PathOf3DOutputFileAtIndex(fileIncrements(iFile));
    t(iFile) = double(ncread(file,'time'));
    
    u3d = double(squeeze(ncread(file, 'u', [1 1 depth_start_index 1], [length(x)/stride length(y)/stride nDepths 1], [stride stride depth_stride 1])));
    v3d = double(squeeze(ncread(file, 'v', [1 1 depth_start_index 1], [length(x)/stride length(y)/stride nDepths 1], [stride stride depth_stride 1])));
    w3d = double(squeeze(ncread(file, 'w', [1 1 depth_start_index 1], [length(x)/stride length(y)/stride nDepths 1], [stride stride depth_stride 1])));
    
    u4d(:,:,:,iFile) = u3d;
    v4d(:,:,:,iFile) = v3d;
    w4d(:,:,:,iFile) = w3d;
end


nMoorings = size(u4d,1)*size(u4d,2);
u3d = reshape(u4d,nMoorings,nDepths, nT);
v3d = reshape(v4d,nMoorings,nDepths, nT);
w3d = reshape(w4d,nMoorings,nDepths, nT);

depths = z(depth_indices);
Lz = wavemodel.Lz;
latitude = wavemodel.latitude;
f0 = wavemodel.f0;

if strcmp(class(wavemodel),'InternalWaveModelExponentialStratification')
    N0 = wavemodel.N0;
    b = wavemodel.b;
    save(outputfile,'u3d','v3d','w3d','t','depths', 'N0', 'b', 'Lz', 'latitude', 'f0');
elseif strcmp(class(wavemodel),'InternalWaveModelConstantStratification')
    N0 = wavemodel.N0;
    save(outputfile,'u3d','v3d','w3d','t','depths', 'N0', 'Lz', 'latitude', 'f0');
else
    error('ahahahahha')
end


dt = t(2)-t(1);
S = zeros(nT+1,nDepths);
for iDepth = 1:nDepths
    cv_mooring = squeeze(u3d(:,iDepth,:) + sqrt(-1)*v3d(:,iDepth,:)).';
    [omega_p, Spp, Snn, Spn] = mspec(dt,cv_mooring,[]);
    omega = [ -flipud(omega_p(2:end)); omega_p];
    S(:,iDepth) = (1/(2*pi))*[flipud(vmean(Snn,2)); vmean(Spp(2:end,:),2)];
end

figure, semilogy(omega*86400/(2*pi),S, 'LineWidth', 2)

GM = GarrettMunkSpectrumConstantStratification(wavemodel.N0,[-wavemodel.Lz 0],wavemodel.latitude);
S_theory = GM.HorizontalVelocitySpectrumAtFrequencies(z(depth_indices),omega)';
S_theory( S_theory<1e-4 ) = nan;

hold on, plot(omega*86400/(2*pi),S_theory, 'k' ,'LineWidth', 2)
xlabel('frequency (cycles per day)'), ylabel('m^2/s^2'), title('horizontal velocity power spectrum')
legend('model output', 'GM')