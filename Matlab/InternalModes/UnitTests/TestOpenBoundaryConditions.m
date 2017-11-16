[rhoFunc, N2Func, zIn] = InternalModes.StratificationProfileWithName('exponential');

top = -500;
N2Func(top)*abs(top)/9.81

integral(N2Func,top,0)
rho1 = integral(rhoFunc,top,0)/top;
rho2 = rhoFunc(top);
(rho2-rho1)/rhoFunc(0)
pt = top*rho1/rhoFunc(0)

latitude = 33;
zBig = linspace(min(zIn),max(zIn),5000)';
zInSmall = [min(zIn) top];
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


%%%%%%%%%%%%%%%%%%%%%%%%%
% Scratch

figure, plot(sqrt(h(1)./h))

% My current thinking is that this doesn't matter... as in, we shouldn't
% worry about open boundary conditions. We simply compute the modes in some
% restricted domain, and the important part is just how the eigenvalue
% changes and how we normalize those modes.