classdef InternalWaveModelConstantStratification < InternalWaveModel
    % InternalWaveModelConstantStratification This implements a simple
    % internal wave model for constant stratification.
    %
    % The usage is simple. First call,
    %   wavemodel = InternalWaveModelConstantStratification(dims, n, latitude, N0);
    % to initialize the model with,
    %   dims        a vector containing the length scales of x,y,z
    %   n           a vector containing the number of grid points of x,y,z
    %   latitude    the latitude of the model (e.g., 45)
    %   N0          the buoyancy frequency of the stratification
    %
    % You must now intialize the model by calling either,
    %   wavemodel.InitializeWithPlaneWave(k0, l0, j0, UAmp, sign);
    % or
    %   wavemodel.InitializeWithGMSpectrum(Amp);
    % where Amp sets the relative GM amplitude.
    %
    % Finally, you can compute u,v,w,zeta at time t by calling,
    %   [u,v] = wavemodel.VelocityFieldAtTime(t);
    %   [w,zeta] = wavemodel.VerticalFieldsAtTime(t);
    %
    % The vertical dimension must have Nz = 2^n or Nz = 2^n + 1 points. If
    % you request the extra point, then the upper boundary will be returned
    % as well. This is designed to match the DCT used by Kraig Winters'
    % model.
    %
    %   See also INTERNALWAVEMODEL and
    %   INTERNALWAVEMODELARBITRARYSTRATIFICATION
    %
    % Jeffrey J. Early
    % jeffrey@jeffreyearly.com
    properties (Access = public)
        N0
        F, G, M
    end
    
    properties (Dependent)
        % These convert the coefficients of Amp_plus.*conj(Amp_plus) and
        % Amp_minus.*conj(Amp_minus) to their depth-integrated averaged
        % values
        A0_HKE_factor
        Apm_HKE_factor
        Apm_VKE_factor
        Apm_PE_factor
        % Same, but for B
        B0_HKE_factor
        B_HKE_factor
        B_PE_factor
    end
    
    properties (Access = protected)
        dctScratch, dstScratch;
        nz % DCT length in the vertical. This doesn't change if the user requests the value at the surface, but Nz will.
        F_cos_ext, G_sin_ext
    end
    
    methods
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Initialization
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function self = InternalWaveModelConstantStratification(dims, n, latitude, N0, rho0)    % MAS 1/11/18
            % rho0 is optional.
            if length(dims) ~=3 || length(n) ~= 3
                error('The dims and n variables must be of length 3. You need to specify x,y,z');
            end
            
            if mod(log2(n(3)),1) == 0
                error('You are implicitly asking for periodic boundary conditions in the vertical. This is not supported.');
            elseif mod(log2(n(3)-1),1) == 0 % user wants the surface point
                nz = n(3)-1; % internally we proceed as if there are n-1 points
            else
                error('The vertical dimension must have 2^n or (2^n)+1 points. This is an artificial restriction.');
            end
            
            % Construct the vertical dimension
            Lz = dims(3);
            Nz = n(3);
            dz = Lz/nz;
            z = dz*(0:Nz-1)' - Lz; % cosine basis (not your usual dct basis, howeve
            
            % Number of modes is fixed for this model.
            nModes = nz-1;
            
            self@InternalWaveModel(dims, n, z, N0*N0*ones(size(z)), nModes, latitude);
            
            if exist('rho0','var')
                self.rho0 = rho0;
            else
                self.rho0 = 1025;
            end
            
            self.N0 = N0;
            self.nz = nz;
            
            rhoFunction = @(z) -(self.N0*self.N0*self.rho0/9.81)*z + self.rho0;
            self.internalModes = InternalModesConstantStratification([N0 self.rho0], [-dims(3) 0],z,latitude);
            
            self.rhobar = rhoFunction(self.z);
            
            % Preallocate this array for a faster dct
            self.dctScratch = zeros(self.Nx,self.Ny,2*self.nz);
            self.dstScratch = complex(zeros(self.Nx,self.Ny,2*self.nz));
            
            g = 9.81;
            self.M = self.J*pi/self.Lz;        % Vertical wavenumber
            h = (1/g)*(self.N0*self.N0-self.f0*self.f0)./(self.M.*self.M+self.K2);
            self.SetOmegaFromEigendepths(h);
            
            % F contains the coefficients for the U-V modes, see equation
            % B12a and B12b in the manuscript
            self.F = (self.h.*self.M)*sqrt(2*g/(self.Lz*(self.N0*self.N0-self.f0*self.f0)));
            
            % G contains the coefficients for the W-modes, see eqn B12c
            self.G = sqrt(2*g/(self.Lz*(self.N0*self.N0-self.f0*self.f0)));
            
            signNorm = -2*(mod(self.J,2) == 1)+1;
            self.F = signNorm .* self.F;
            self.G = signNorm * self.G;
        end
        
        function [u,v,w] = AnalyticalSolutionAtFrequency(self, t, x, y, z, omega, alpha, j0, phi, U)
            m = j0*pi/self.Lz;
            gh = m.*m * (self.N0*self.N0 - omega.*omega);
            K = sqrt( (omega.*omega - self.f0*self.f0)./gh );
            k0 = K.*cos(alpha);
            l0 = K.*sin(alpha);
            
            [u,v,w] = self.AnalyticalSolution(t, x, y, z, k0, l0, m, K, alpha, omega, phi, U);
        end
        
        function u = AnalyticalSolutionVectorAtWavenumber(self, t, x, k0, l0, j0, phi, U)
            xsize = size(x);
            if xsize(1) == 3
                [u,v,w] = self.AnalyticalSolutionAtWavenumber(t, x(1,:), x(2,:), x(3,:), k0, l0, j0, phi, U);
                u = cat(1,u,v,w);
            else
                [u,v,w] = self.AnalyticalSolutionAtWavenumber(t, x(:,1), x(:,2), x(:,3), k0, l0, j0, phi, U);
                u = cat(2,u,v,w);
            end
        end
        
        function [u,v,w] = AnalyticalSolutionAtWavenumber(self, t, x, y, z, k0, l0, j0, phi, U)
            alpha=atan2(l0,k0);
            K = sqrt( k0^2 + l0^2);
            m = j0*pi/self.Lz;
            gh = (self.N0 * self.N0 - self.f0*self.f0)./( m.*m + K.*K);
            omega = sqrt( gh .* K.*K + self.f0*self.f0 );
            
            [u,v,w] = self.AnalyticalSolution(t, x, y, z, k0, l0, m, K, alpha, omega, phi, U);
        end
        
        function [u,v,w] = AnalyticalSolution(self, t, x, y, z, k0, l0, m, K, alpha, omega, phi, U)
            theta = k0.*x + l0.*y + omega.*t + phi;
            cos_theta = cos(theta);
            sin_theta = sin(theta);
            u = U*(cos(alpha)*cos_theta + (self.f0/omega)*sin(alpha)*sin_theta).*cos(m*z);
            v = U*(sin(alpha)*cos_theta - (self.f0/omega)*cos(alpha)*sin_theta).*cos(m*z);
            w = (U*K/m) * sin_theta .* sin(m*z);
        end
        
        function InitializeWithHorizontalVelocityAndDensityPerturbationFields(self, t, u, v, rho_prime)
            zeta = self.g * rho_prime /(self.rho0 * self.N0 * self.N0);
            self.InitializeWithHorizontalVelocityAndIsopycnalDisplacementFields(t,u,v,zeta);
        end
        
        function InitializeWithIsopycnalDisplacementField(self, zeta)
            % Note that you will lose any 'mean' zeta, because technically
            % this is the perturbation *from* a mean.
            zeta_bar = self.TransformFromSpatialDomainWithG(zeta);
            
            Kh = self.Kh;
            Kh(Kh<1e-14) = 1;
            negate_zeta = abs(self.Omega)./(Kh .* sqrt(self.h));
            A_plus = -zeta_bar .* negate_zeta ./ self.G; % extra factor from constant stratification case.
            A_minus = A_plus;
            A_plus(self.K < 0) = 0;
            A_minus(self.K > 0) = 0;
             self.GenerateWavePhases(A_plus,zeros(size(self.K)));
%             self.GenerateWavePhases(A_plus,A_minus);
        end
        
        function InitializeGeostrophicSolutionWithRhoPrimeField(self, rho_prime)
            self.InitializeGeostrophicSolutionWithIsopycnalDisplacementField(-rho_prime/((self.rho0/self.g)*self.N0*self.N0));
        end
        
        function InitializeGeostrophicSolutionWithIsopycnalDisplacementField(self, zeta)
            self.B = self.TransformFromSpatialDomainWithG(zeta) ./ self.G;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Computes the phase information given the amplitudes (internal)
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
        function PrecomputeExternalWaveCoefficients(self)
            PrecomputeExternalWaveCoefficients@InternalWaveModel(self)
            if self.norm_ext == Normalization.kConstant
                g = 9.81;
                coeff = sqrt(2*g/(self.Lz*(self.N0*self.N0-self.f0*self.f0)));
                self.F_cos_ext = coeff * ( self.h_ext .* self.k_z_ext );
                self.G_sin_ext = coeff * ones(size(self.h_ext));
            elseif self.norm_ext == Normalization.uMax
                self.F_cos_ext = ones(size(self.h_ext));
                self.G_sin_ext = 1./(self.h_ext .* self.k_z_ext);
            end
        end
        
        function rho = RhoBarAtDepth(self,z)
            g = 9.81;
            rho = -(self.N0*self.N0*self.rho0/g)*z + self.rho0;
        end
        
        function N2 = N2AtDepth(self,z)
            N2 = self.N0 * self.N0 * ones(size(z));
        end
        
        
        function value = get.A0_HKE_factor(self)
             value = self.Lz/2;
        end
        function value = get.Apm_HKE_factor(self)
            % This currently differs from the definition in the manuscript
            % by a factor of h. The missing factor of 1/2 is the c.c.
            value = (1 + self.f0*self.f0./(self.Omega.*self.Omega)) .* (self.N0*self.N0 - self.Omega.*self.Omega) / (2 * (self.N0*self.N0 - self.f0*self.f0) );
        end
        function value = get.Apm_VKE_factor(self)
            value = (self.Omega.*self.Omega - self.f0*self.f0) / (2 * (self.N0*self.N0 - self.f0*self.f0) );
        end
        function value = get.Apm_PE_factor(self)
            value = self.N0*self.N0 .* (self.Omega.*self.Omega - self.f0*self.f0) ./ (2 * (self.N0*self.N0 - self.f0*self.f0) * self.Omega.*self.Omega );
        end
        function value = get.B0_HKE_factor(self)
            value = (self.g^2/(self.f0*self.f0)) * self.K2(:,:,1) * self.Lz/2;
        end
        function value = get.B_HKE_factor(self)
            value = (self.g/(self.f0*self.f0)) * (self.Omega.*self.Omega - self.f0*self.f0) .* (self.N0*self.N0 - self.Omega.*self.Omega) / (2 * (self.N0*self.N0 - self.f0*self.f0) );
        end
        function value = get.B_PE_factor(self)
            value = self.g*self.N0*self.N0/(self.N0*self.N0-self.f0*self.f0)/2;
        end
    end
    
    methods %(Access = protected)
        
        function ratio = UmaxGNormRatioForWave(self,k0, l0, j0)
            if j0 == 0
                ratio = 1;
            else
                myH = self.h(k0+1,l0+1,j0);
                m = j0*pi/self.Lz;
                g = 9.81;
                F_coefficient = myH * m * sqrt(2*g/self.Lz)/sqrt(self.N0^2 - self.f0^2);
                ratio = sqrt(myH)/F_coefficient;
            end
        end     
                
        % size(z) = [N 1]
        % size(waveIndices) = [1 M]
        function F = ExternalUVModeAtDepth(self, z, iMode)
            % Called by the superclass when advecting particles spectrally.
            F = self.F_cos_ext(iMode) * cos( z * self.k_z_ext(iMode) );
        end
        
        function G = ExternalWModeAtDepth(self, z, iMode)
            % Called by the superclass when advecting particles spectrally.
            G = self.G_sin_ext(iMode) * sin( z * self.k_z_ext(iMode) );
        end
                
        function F = InternalUVModeAtDepth(self, z, iMode)
            % Called by the superclass when advecting particles spectrally.
            k_z = self.j_int(iMode)*pi/self.Lz;
            g = 9.81;
            coeff = sqrt(2*g/(self.Lz*(self.N0*self.N0-self.f0*self.f0)));
            F = coeff * ( self.h_int(iMode) * k_z ) .* cos(z * k_z); % [N M]
        end
        
        function G = InternalWModeAtDepth(self, z, iMode)
            % Called by the superclass when advecting particles spectrally.
            k_z = self.j_int(iMode)*pi/self.Lz;
            g = 9.81;
            coeff = sqrt(2*g/(self.Lz*(self.N0*self.N0-self.f0*self.f0)));
            G = coeff * sin(z * k_z); % [N M]
        end
                
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Computes the phase information given the amplitudes (internal)
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function u = TransformToSpatialDomainWithBarotropicFMode(self, u_bar)
            u = self.Nx*self.Ny*ifft(ifft(u_bar,self.Nx,1),self.Ny,2,'symmetric');
            u = repmat(u,[1 1 self.Nz]);
        end
        
        function u = TransformToSpatialDomainWithF(self, u_bar)
            % Note that the extra multiplication by self.F could be
            % precomputed---but we keep it for simplicity, at the cost of
            % speed.
            
            % Here we use what I call the 'Fourier series' definition of the ifft, so
            % that the coefficients in frequency space have the same units in time.
            u = self.Nx*self.Ny*ifft(ifft(u_bar.*self.F,self.Nx,1),self.Ny,2,'symmetric');
            
            % Re-order to convert to an fast cosine transform
            % There's a lot of time spent here, and below taking the real
            % part.
            self.dctScratch = cat(3, zeros(self.Nx,self.Ny), 0.5*u(:,:,1:self.nz-1), zeros(self.Nx,self.Ny), 0.5*u(:,:,self.nz-1:-1:1));
%             self.dctScratch(:,:,2:self.nz) =  0.5*u(:,:,1:self.nz-1); % length= nz-1
%             self.dctScratch(:,:,self.nz+1) =  u(:,:,self.nz); % length 1
%             self.dctScratch(:,:,(self.nz+2):(2*self.nz)) = 0.5*u(:,:,self.nz-1:-1:1); % length nz-1
            
            u = fft(self.dctScratch,2*self.nz,3);
            if self.performSanityChecks == 1
                ratio = max(max(max(abs(imag(u)))))/max(max(max(abs(real(u)))));
                if ratio > 1e-6
                    fprintf('WARNING: The inverse cosine transform reports an unreasonably large imaginary part, %.2g.\n',ratio);
                end
            end
            % should not have to call real, but for some reason, with enough
            % points, it starts generating some small imaginary component.
            u = real(u(:,:,1:self.Nz)); % Here we use Nz (not nz) because the user may want the end point.
        end
        
        function w = TransformToSpatialDomainWithG(self, w_bar )
            % Here we use what I call the 'Fourier series' definition of the ifft, so
            % that the coefficients in frequency space have the same units in time.
            w = self.Nx*self.Ny*ifft(ifft(w_bar.* self.G,self.Nx,1),self.Ny,2,'symmetric');
            
            % Re-order to convert to an fast cosine transform
            self.dstScratch = sqrt(-1)*cat(3, zeros(self.Nx,self.Ny), 0.5*w(:,:,1:self.nz-1), zeros(self.Nx,self.Ny), -0.5*w(:,:,self.nz-1:-1:1));
            
            w = fft( self.dstScratch,2*self.nz,3);
            if self.performSanityChecks == 1
                ratio = max(max(max(abs(imag(w)))))/max(max(max(abs(real(w)))));
                if ratio > 1e-6
                    fprintf('WARNING: The inverse sine transform reports an unreasonably large imaginary part, %.2g.\n',ratio);
                end
            end
            % should not have to call real, but for some reason, with enough
            % points, it starts generating some small imaginary component.
            w = real(w(:,:,1:self.Nz)); % Here we use Nz (not nz) because the user may want the end point.
        end
                
        function u_bar = TransformFromSpatialDomainWithBarotropicFMode(self, u)
            % Consistent with the DCT-I, the end points only have half the
            % width of the other points.
            u(:,:,1) = 0.5*u(:,:,1);
            u(:,:,end) = 0.5*u(:,:,end);
            u_bar = fft(fft(sum(u,3)/(self.Nz-1),self.Nx,1),self.Ny,2)/self.Nx/self.Ny;
        end
        
        function u_bar = TransformFromSpatialDomainWithF(self, u)
            % df = 1/(2*(Nz-1)*dz)
            % nyquist = (Nz-1)*df
            self.dctScratch = ifft(cat(3,u,u(:,:,self.nz:-1:2)),2*self.nz,3);
            u_bar = 2*real(self.dctScratch(:,:,2:self.nz)); % we *ignore* the barotropic mode, starting at 2, instead of 1 in the transform
            u_bar = fft(fft(u_bar,self.Nx,1),self.Ny,2)./self.F/self.Nx/self.Ny;
        end
        
        function w_bar = TransformFromSpatialDomainWithG(self, w)
            % df = 1/(2*(Nz-1)*dz)
            % nyquist = (Nz-2)*df
            self.dstScratch = ifft(cat(3,w,-w(:,:,self.nz:-1:2)),2*self.nz,3);
            w_bar = 2*imag(self.dstScratch(:,:,2:self.nz));
            w_bar = fft(fft(w_bar,self.Nx,1),self.Ny,2)./self.G/self.Nx/self.Ny;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Compute full spectral transforms to take derivatives with
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [u_bar, K, L, M] = TransformFromSpatialDomainWithFFull(self, u)
            self.dctScratch = ifft(cat(3,u,u(:,:,self.nz:-1:2)),2*self.nz,3);
            u_bar = 2*real(self.dctScratch(:,:,1:self.nz+1)); % we *include* the barotropic mode, starting at 1, instead of 2 in the transform
            u_bar = fft(fft(u_bar,self.Nx,1),self.Ny,2)/self.Nx/self.Ny;
            
            u_bar(:,:,2:end) = u_bar(:,:,2:end)./self.F;
            
            m = (pi/self.Lz)*(0:(self.Nz-1));
            [K,L,M] = ndgrid(self.k,self.l,m);
        end
        
        function u = TransformToSpatialDomainWithFFull(obj, u_bar)
            % Here we use what I call the 'Fourier series' definition of the ifft, so
            % that the coefficients in frequency space have the same units in time.
            u = obj.Nx*obj.Ny*ifft(ifft(u_bar,obj.Nx,1),obj.Ny,2,'symmetric');
            
            % Re-order to convert to an fast cosine transform
            obj.dctScratch = cat(3, 0.5*u(:,:,1:obj.nz), u(:,:,obj.nz), 0.5*u(:,:,obj.nz:-1:2));
            
            u = fft(obj.dctScratch,2*obj.nz,3);
            if obj.performSanityChecks == 1
                ratio = max(max(max(abs(imag(u)))))/max(max(max(abs(real(u)))));
                if ratio > 1e-6
                    fprintf('WARNING: The inverse cosine transform reports an unreasonably large imaginary part, %.2g.\n',ratio);
                end
            end
            % should not have to call real, but for some reason, with enough
            % points, it starts generating some small imaginary component.
            u = real(u(:,:,1:obj.Nz)); % Here we use Nz (not nz) because the user may want the end point.
        end
        
    end
end


