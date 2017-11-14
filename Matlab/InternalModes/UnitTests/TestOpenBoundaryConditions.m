[rhoFunc, N2Func, zIn] = InternalModes.StratificationProfileWithName('exponential');

latitude = 33;
zBig = linspace(min(zIn),max(zIn),5000)';
zInSmall = [min(zIn) -1400];
zSmall = linspace(min(zInSmall),max(zInSmall),5000)';

im = InternalModes(rhoFunc,zIn,zSmall,latitude,'method','spectral');

imSmall = InternalModes(rhoFunc,zInSmall,zSmall,latitude,'method','spectral');
imSmall.upperBoundary = UpperBoundary.open;


[F,G,h] = im.ModesAtWavenumber(0.0);
figure
subplot(1,2,1)
plot(F(:,1:2:8),zSmall)
subplot(1,2,2)
plot(G(:,1:2:8),zSmall)

[Fs,Gs,hs] = imSmall.ModesAtWavenumber(0.0);
figure
subplot(1,2,1)
plot(Fs(:,1:4),zSmall)
subplot(1,2,2)
plot(Gs(:,1:4),zSmall)