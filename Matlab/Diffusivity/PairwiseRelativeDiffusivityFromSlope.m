function [r2,kappa_r,std_error] = PairwiseRelativeDiffusivityFromSlope( t, x, y, theBins )
%PairwiseRelativeDiffusivityFromSlope
%
% Returns the *relative* diffusivity between pairs of drifters as a
% function of initial separation. The results are sorted into bins with
% edges given by "theBins".
%
% Note that the relative diffusivity is twice the usual diffusivity you'd
% get from just computing the rate-of-change of 2nd moment of the mass of
% drifters. So it's double what you'd expect from measuring a tracer.
%
% The algorithm computes the mean-square separation of particle pairs at a
% given time, averages the mean-square, *then* computes the slope of those
% mean separations. The slope is computing assuming an intercept of zero.
%
% This is different than the algorithm used in PairwiseRelativeDiffusivityFromSlopeScatter

nDrifters = size(x,2);

% make sure t is a column vector
t = reshape(t,[],1);

nBins = length(theBins);
D2 = zeros(length(t),nBins); % mean-square distance vs time, for each bin
r0 = zeros(1,nBins); % initial separation
nReps = zeros(1,nBins); % number of samples in this bin.

stride = 1;
for iDrifter=1:stride:nDrifters
    for jDrifter = (iDrifter+1):stride:nDrifters        
        q = x(:,iDrifter) - x(:,jDrifter);
        r = y(:,iDrifter) - y(:,jDrifter);
        
        initialSeparation = sqrt(q(1)^2 + r(1)^2);
        iBin = find(initialSeparation > theBins,1,'last');
        
        nReps(iBin) = nReps(iBin) + 1;
        r0(iBin) = r0(iBin) + initialSeparation;
                
        % Now remove the initial conditions.
        q = q-q(1);
        r = r-r(1);
        
        % squared-separation distance as a function of time.
        D2(:,iBin) = D2(:,iBin) + q.^2 + r.^2;
    end
end

D2 = D2./nReps;
r0 = r0./nReps;

r2 = zeros(nBins,1);
kappa_r = zeros(nBins,1);
std_error = zeros(nBins,1);

for iBin = 1:nBins
    X = t;
    Y = D2(:,iBin);
    
    %% Calculation of Standard Error Without Intercept
    % https://www.mathworks.com/matlabcentral/answers/373940-how-does-matlab-calculate-standard-error-in-fitlm
    n = length(X);                                       %  Number of observations
    Slope = sum(X.*Y)/sum(X.^2);                         %  Calculates slope
    yfit=X*Slope;                                        %  Fitted response values based on the slope
    r = Y - yfit;                                        %  r is the residuals, which is the observed minus fitted values
    SSE = sum(r.^2);                                     %  SSE is the sum of squared errors
    MSE=SSE/(n-1);                                       %  Mean Squared Error
    SE=sqrt(MSE/sum(X.^2));
    
    r2(iBin) = r0(iBin)^2;
    kappa_r(iBin) = Slope/4;
    std_error(iBin) = SE/4;
     
    
%     [p,bint,mu]=polyfit(tBin{iBin},D2Bin{iBin},1);
%     m = (p(1)/mu(2));
%     b = p(2)-p(1)*mu(1)/mu(2);
%     
%     SSR = sum((D2Bin{iBin} - (m*tBin{iBin}+b)).^2)/(length(tBin{iBin})-2);
%     ESS = sum((tBin{iBin} - mean(tBin{iBin})).^2);
%     
%     kappa_r(iBin) = m/4;
%     std_error(iBin) = sqrt(SSR/ESS)/4;
%     
%     b_err = sqrt(diag((bint.R)\inv(bint.R'))./bint.normr.^2./bint.df);
    
end

