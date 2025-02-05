classdef ModelDiagnostics < handle
    % ModelDiagnostics
    properties (Access = public)
        Lx, Ly, Lz % Domain size
        Nx, Ny, Nz % Number of points in each direction
        latitude
        
        x, y, z
        k, l, j
        X,Y,Z
        K,L,J
        
        rhoBar % mean density, function of z
        rho0 % density at the surface
        
        N2 % will be forced to be 1x1xLz
        Nmax % sqrt(max(N2))
        K2, Kh, f0
        
        % isotropic wavenumber axis, its spacing, and indices into Kh
        kAxis, dK, kIndices
        
        u,v,w,rhoPrime
    end
    
    properties (Dependent)
        % Alternative forms of density background and density anomaly
        bbar        % bbar = -(g/rho_0)*rhobar
        b           % buoyancy anomaly, b = -(g/rho_0)*rhoPrime
        eta         % eta = - rhoPrime/rhobar_z
        
        
        bbar_z      % bbar_z = N^2 = -(g/rho_0)*rhobar_z
        rhoBar_z    % rhobar_z = -(rho0/g)*N^2
        
        % Single derivatives of the primary variables
        u_x, u_y, u_z
        v_x, v_y, v_z
        w_x, w_y, w_z
        b_x, b_y, b_z
        eta_x, eta_y, eta_z
        
        % Components of vorticity
        vorticity_x	% w_y - v_z
        vorticity_y	% u_z - w_x
        vorticity_z	% v_x - u_y
    end
    
    properties (Constant)
        g = 9.81;
        L_gm = 1.3e3; % thermocline exponential scale, meters
        N_gm = 5.2e-3; % reference buoyancy frequency, radians/seconds
        E_gm = 6.3e-5; % non-dimensional energy parameter
        E = (1.3e3)*(1.3e3)*(1.3e3)*(5.2e-3)*(5.2e-3)*(6.3e-5);
    end
    
    methods
        function self = ModelDiagnostics(dims, n, latitude, rhoBar, N2)
            if length(dims) ~=3 || length(n) ~= 3
                error('The dims and n variables must be of length 3. You need to specify x,y,z');
            end
            
            if length(rhoBar) ~= n(3) || length(N2) ~= n(3)
               error('N2 must have the same number of points as the z dimension'); 
            end
            
            self.Lx = dims(1);
            self.Ly = dims(2);
            self.Lz = dims(3);
            
            self.Nx = n(1);
            self.Ny = n(2);
            self.Nz = n(3);
            
            self.latitude = latitude;
            
            dx = self.Lx/self.Nx;
            dy = self.Ly/self.Ny;
            dz = self.Lz/(self.Nz-1);
            self.x = dx*(0:self.Nx-1)'; % periodic basis
            self.y = dy*(0:self.Ny-1)'; % periodic basis
            self.z = dz*(0:self.Nz-1)' - self.Lz; % cosine basis (not your usual dct basis, however)
            
            self.rhoBar = rhoBar;
            self.rho0 = rhoBar(end);
            
            % Let's make N2 exist in the 3rd dimension, for east
            % multiplication.
            if ~exist('N2','var')
                N2 = -(self.g/self.rho0)*DiffCosine(self.z,rhoBar);
            end
            self.N2 = reshape(N2,1,1,[]);
            self.Nmax = sqrt(max(self.N2));
            
            % Spectral domain, in radians
            if self.Nx > 0 && self.Lx > 0
                dk = 1/self.Lx;          % fourier frequency
                self.k = 2*pi*([0:ceil(self.Nx/2)-1 -floor(self.Nx/2):-1]*dk)';
            else
                self.k = 0;
            end
            
            if self.Ny > 0 && self.Ly > 0
                dl = 1/self.Ly;          % fourier frequency
                self.l = 2*pi*([0:ceil(self.Ny/2)-1 -floor(self.Ny/2):-1]*dl)';
            else
                self.l = 0;
            end
            
            self.j = (1:(self.Nz-1))';
            
            [K,L,J] = ndgrid(self.k,self.l,self.j);
            [X,Y,Z] = ndgrid(self.x,self.y,self.z);
            
            self.L = L; self.K = K; self.J = J;
            self.X = X; self.Y = Y; self.Z = Z;
            
            self.f0 = 2 * 7.2921E-5 * sin( self.latitude*pi/180 );
            self.K2 = self.K.*self.K + self.L.*self.L;   % Square of the horizontal wavenumber
            self.Kh = sqrt(self.K2);
            
            self.BuildIsotropicWavenumberAxis();
        end
        
        function BuildIsotropicWavenumberAxis(self)
            % Create a reasonable wavenumber axis, then find which indices
            % in Kh belong in the buckets of the kAxis.
            allKs = unique(reshape(abs(self.Kh),[],1),'sorted');
            self.dK = max(diff(allKs));
            self.kAxis = 0:self.dK:max(allKs);
            self.kIndices = cell( length(self.kAxis), 1);
            for i = 1:length(self.kAxis)
                self.kIndices{i} = find( squeeze(self.Kh(:,:,1)) >= self.kAxis(i)-self.dK/2 & squeeze(self.Kh(:,:,1)) < self.kAxis(i)+self.dK/2 );
            end
        end
        
        function [S,k] = MakeIsotropicWavenumberSpectrumFromXY(self, u)
            % Given u, with dimensions x,y and possibly z, this assumes
            % that x and y should be treated isotropically, and builds an
            % isotropic wavenumber spectrum. The returned object S will
            % have dimension [length(k) Nz].
            %
            % Preserves variance in the following way,
            % var = squeeze(mean(mean((self.u).^2,1),2))
            % var = squeeze(sum(S,1)*(k(2)-k(1)))
            
            % should be the same as fft(fft(u,1),2)/Nx/Ny
            u_bar = FourierTransformForward(self.x,u,1);
            u_bar = FourierTransformForward(self.y,u_bar,2);
            
            % S_u is now the spectrum (see the notes in
            % FourierTransformForward) but note that we are using radians!
            S_u = self.Lx*self.Ly* ( u_bar.*conj(u_bar) )/(2*pi)^2;
            
            % Multiply in order to convert from spectral density to
            % variance---the sum(S_u) should be total variance.
            dk = self.k(2)-self.k(1);
            dl = self.l(2)-self.l(1);
            S_u = dk*dl*S_u;
            
            S = zeros(length(self.kAxis),size(u,3));
            for iK = 1:length(self.kAxis)
                for iJ = 1:size(u,3)
                    ulvl = squeeze(S_u(:,:,iJ));
                    S(iK,iJ) = sum(ulvl(self.kIndices{iK}))/self.dK;
                end
            end
            k = self.kAxis;
        end
        
        
        function [S,m] = MakeVerticalWavenumberSpectrumWithCosineTransform(self,u,dim)
            [u_bar, m] = CosineTransformForward( self.z, u, dim );
            S = self.Lz* ( u_bar .* conj(u_bar) );
            
            % We're now going to correct the zero and Nyquist frequencies
            % so that the spectral sum does the right thing
            
            % move the dim to the first dimension
            % [x y dim] -> [dim x y]
            S = shiftdim(S,dim-1);
            S(1,:) = S(1,:)/2;
            S(end,:) = S(end,:)*2;
            
            % now move the dim back to where it was
            S = shiftdim(S,ndims(S)-(dim-1));
            
            S = S/(2*pi);
            m = m*(2*pi);
        end
        
        function [S,m] = MakeVerticalWavenumberSpectrumWithSineTransform(self,u,dim)
            [u_bar, m] = SineTransformForward( self.z, u, dim, 'both' );
            S = self.Lz* ( u_bar .* conj(u_bar) );
                        
            S = S/(2*pi);
            m = m*(2*pi);
        end
         
        function [S,k,m] = MakeHorizontalAndVerticalWavenumberSpectrumCosine(self, u)
            % Given u, with dimensions x,y and possibly z, this assumes
            % that x and y should be treated isotropically, and builds an
            % isotropic wavenumber spectrum. The returned object S will
            % have dimension [length(k) Nz].
            %
            % Preserves variance in the following way,
            % var = squeeze(mean(mean((self.u).^2,1),2))
            % var = squeeze(sum(S,1)*(k(2)-k(1)))
            
            % should be the same as fft(fft(u,1),2)/Nx/Ny
            u_bar = FourierTransformForward(self.x,u,1);
            u_bar = FourierTransformForward(self.y,u_bar,2);
            [u_bar, m] = CosineTransformForward( self.z, u_bar, 3 );
            
            % S_u is now the spectrum (see the notes in
            % FourierTransformForward) but note that we are using radians!
            S_u = self.Lx*self.Ly*self.Lz*( u_bar.*conj(u_bar) )/(2*pi)^3;
            
            % Multiply in order to convert from spectral density to
            % variance---the sum(S_u) should be total variance.
            dk = self.k(2)-self.k(1);
            dl = self.l(2)-self.l(1);
            S_u = dk*dl*S_u;
            
            S = zeros(length(self.kAxis),size(u,3));
            for iK = 1:length(self.kAxis)
                for iJ = 1:size(u,3)
                    ulvl = squeeze(S_u(:,:,iJ));
                    if iJ == 1
                        S(iK,iJ) = sum(ulvl(self.kIndices{iK}))/self.dK/2;
                    elseif iJ == size(u,3)
                        S(iK,iJ) = 2*sum(ulvl(self.kIndices{iK}))/self.dK;
                    else
                        S(iK,iJ) = sum(ulvl(self.kIndices{iK}))/self.dK;
                    end
                end
            end
            k = self.kAxis;
        end
        
        function [S,k,m] = MakeHorizontalAndVerticalWavenumberSpectrumSine(self, u)
            % Given u, with dimensions x,y and possibly z, this assumes
            % that x and y should be treated isotropically, and builds an
            % isotropic wavenumber spectrum. The returned object S will
            % have dimension [length(k) Nz].
            %
            % Preserves variance in the following way,
            % var = squeeze(mean(mean((self.u).^2,1),2))
            % var = squeeze(sum(S,1)*(k(2)-k(1)))
            
            % should be the same as fft(fft(u,1),2)/Nx/Ny
            u_bar = FourierTransformForward(self.x,u,1);
            u_bar = FourierTransformForward(self.y,u_bar,2);
            [u_bar, m] = SineTransformForward( self.z, u_bar, 3,'both' );
            
            % S_u is now the spectrum (see the notes in
            % FourierTransformForward) but note that we are using radians!
            S_u = self.Lx*self.Ly*self.Lz ( u_bar.*conj(u_bar) )/(2*pi)^3;
            
            % Multiply in order to convert from spectral density to
            % variance---the sum(S_u) should be total variance.
            dk = self.k(2)-self.k(1);
            dl = self.l(2)-self.l(1);
            S_u = dk*dl*S_u;
            
            S = zeros(length(self.kAxis),size(u,3));
            for iK = 1:length(self.kAxis)
                for iJ = 1:size(u,3)
                    ulvl = squeeze(S_u(:,:,iJ));
                    S(iK,iJ) = sum(ulvl(self.kIndices{iK}))/self.dK;
                end
            end
            k = self.kAxis;
        end
        
        
        
        function InitializeWithHorizontalVelocityAndDensityPerturbationFields(self, u, v, w, rhoPrime)
            self.u = u;
            self.v = v;
            self.w = w;
            self.rhoPrime = rhoPrime;
        end
        
        function InitializeWithHorizontalVelocityAndIsopycnalDisplacementFields(self, u, v, w, eta)
            self.u = u;
            self.v = v;
            self.w = w;
            self.rhoPrime = -eta .* self.rhoBar_z;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        %  Other ways of expressing the density perturbation
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function value = get.bbar(self)
            value = -(self.g/self.rho0)*self.rhoBar;
        end
        
        function value = get.b(self)
            value = -(self.g/self.rho0)*self.rhoPrime;
        end
        
        function value = get.eta(self)
            value = -self.rhoPrime./self.rhoBar_z;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        %  Other ways of expressing the background density gradient
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function value = get.bbar_z(self)
            value = self.N2;
        end
        
        function value = get.rhoBar_z(self)
            value = -(self.rho0/self.g)*self.N2;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        %  Single derivatives of the primary variables
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        function value = get.u_x(self)
            value = DiffFourier(self.x,self.u,1,1);
        end
        
        function value = get.u_y(self)
            value = DiffFourier(self.y,self.u,1,2);
        end
        
        function value = get.u_z(self)
            value = DiffCosine(self.z,self.u);
        end
        
        function value = get.v_x(self)
            value = DiffFourier(self.x,self.v,1,1);
        end
        
        function value = get.v_y(self)
            value = DiffFourier(self.y,self.v,1,2);
        end
        
        function value = get.v_z(self)
            value = DiffCosine(self.z,self.v);
        end
        
        function value = get.w_x(self)
            value = DiffFourier(self.x,self.w,1,1);
        end
        
        function value = get.w_y(self)
            value = DiffFourier(self.y,self.w,1,2);
        end
        
        function value = get.w_z(self)
            value = DiffSine(self.z,self.w);
        end
        
        function value = get.b_x(self)
            value = DiffFourier(self.x,self.b,1,1);
        end
        
        function value = get.b_y(self)
            value = DiffFourier(self.y,self.b,1,2);
        end
        
        function value = get.b_z(self)
            value = DiffSine(self.z,self.b);
        end
        
        function value = get.eta_x(self)
            value = DiffFourier(self.x,self.eta,1,1);
        end
        
        function value = get.eta_y(self)
            value = DiffFourier(self.y,self.eta,1,2);
        end
        
        function value = get.eta_z(self)
            value = DiffSine(self.z,self.eta);
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        %  Useful derived quantities
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function value = get.vorticity_x(self)
            value = self.w_y - self.v_z; % w_y - v_z
        end
        
        function value = get.vorticity_y(self)
            value = self.u_z - self.w_x; % u_z - w_x
        end
        
        function value = get.vorticity_z(self)
            value = self.v_x - self.u_y; % v_x - u_y
        end
        

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Measures of Potential Vorticity
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
        function PV = ErtelPV(self,noBackground)
            %% Ertel PV,  1/s^3
            % PV = (N^2(z) \hat{k} + \nabla b) \cdot (f \hat{k} + \omega)
            %
            % The background PV, f0*N2, can be safely eliminated in constant
            % stratification, but it remains important in variable
            % stratification due to vertical advection.
            
            PVx = self.vorticity_x .* self.b_x;
            PVy = self.vorticity_y .* self.b_y;
            if exist('noBackground','var') && noBackground == 1
                PVz = (self.f0 + self.vorticity_z) .* self.b_z + self.vorticity_z .* self.bbar_z;
            else
                PVz = (self.f0 + self.vorticity_z) .* (self.b_z + self.bbar_z);
            end
            
            PV = PVx + PVy + PVz;
        end
        
        function PV = LinearErtelPV(self,noBackground)
            %% Linear Ertel PV  (the linear terms in Ertel PV) 1/s^3
            % PV = f_0 b_z + (f0 + vorticity_z) *N^2(z)
            %
            % Same as above, the background PV, f0*N2, can be safely
            % eliminated in constant stratification, but it remains
            % important in variable stratification due to vertical
            % advection.
            
            if exist('noBackground','var') && noBackground == 1
                PV = self.f0 * self.b_z + self.vorticity_z .* self.N2;
            else
                PV = self.f0 * self.b_z + (self.f0 + self.vorticity_z) .* self.N2;
            end
        end
        
        function PV = QGPV(self)
            %% QG PV, quasigeostrophic potential vorticity
            % PV = N^2 (-f_0 eta_z + \zeta_z) where eta = -rho/rhobar_z
            %
            % This is only the same as linear Ertel PV when N^2 is constant
            % with no background. But, these are fundamentally different
            % quantities, based on different approximations.
            
            PV = self.N2 .* ( self.vorticity_z - self.f0 * self.eta_z );
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Variances and energy as a function of depth
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [Euv,z] = HorizontalVelocityVariance(self)
            %% Horizontal velocity variance as a function of depth, m^2/s^2
            %
            Euv = squeeze(mean(mean((self.u).^2 + (self.v).^2,1),2));
            z = self.z;
        end
        
        function [Ew,z] = VerticalVelocityVariance(self)
            %% Vertical velocity variance as a function of depth, m^2/s^2
            %
            Ew = squeeze(mean(mean((self.w).^2,1),2));
            z = self.z;
        end
        
        function [Eeta,z] = IsopycnalVariance(self)
            %% Isopycnal velocity variance as a function of depth, m^2
            %
            Eeta = squeeze(mean(mean((self.eta).^2,1),2));
            z = self.z;
        end
        
        function [Euv,z] = HorizontalVelocityVarianceWKB(self)
            %% WKB scaled horizontal velocity variance as a function of depth, m^2/s^2
            %
            Euv = (self.N_gm./sqrt(self.N2)) .* self.HorizontalVelocityVariance();
            z = self.z;
        end
        
        function [Ew,z] = VerticalVelocityVarianceWKB(self)
            %% WKB scaled vertical velocity variance as a function of depth, m^2/s^2
            %
            Ew = (sqrt(self.N2)./self.N_gm) .* self.VerticalVelocityVariance();
            z = self.z;
        end
        
        function [Eeta,z] = IsopycnalVarianceWKB(self)
            %% WKB scaled sopycnal velocity variance as a function of depth, m^2
            %
            Eeta = (sqrt(self.N2)./self.N_gm) .* self.IsopycnalVariance();
            z = self.z;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Variances and energy as a function of horizontal wavenumber
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [S,k,z] = HorizontalVelocitySpectrumAtWavenumbers(self)
            %% Horizontal velocity wavenumber spectrum as a function of depth, m^3/s^2
            %
            S = self.MakeIsotropicWavenumberSpectrumFromXY(self.u+sqrt(-1)*self.v);
            k = self.kAxis;
            z = self.z;
        end
        
        function [S,k,z] = VerticalVelocitySpectrumAtWavenumbers(self)
            %% Vertical velocity wavenumber spectrum as a function of depth, m^3/s^2
            %
            S = self.MakeIsotropicWavenumberSpectrumFromXY(self.w);
            k = self.kAxis;
            z = self.z;
        end
        
        function [S,k,z] = IsopycnalSpectrumAtWavenumbers(self)
            %% Isopycnal wavenumber spectrum as a function of depth, m^3
            %
            S = self.MakeIsotropicWavenumberSpectrumFromXY(self.eta);
            k = self.kAxis;
            z = self.z;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Variances and energy as a function of horizontal and vertical wavenumber
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [S,k,m] = HorizontalVelocitySpectrumAtHorizontalAndVerticalWavenumbers(self)
            %% Horizontal velocity wavenumber spectrum as a function of depth, m^4/s^2
            
            [S,k,m] = self.MakeHorizontalAndVerticalWavenumberSpectrumCosine(self.u + sqrt(-1)*self.v);
        end
        
        function [S,k,m] = VerticalVelocitySpectrumAtHorizontalAndVerticalWavenumbers(self)
            %% Vertical velocity wavenumber spectrum as a function of depth, m^4/s^2
            
            [S,k,m] = self.MakeHorizontalAndVerticalWavenumberSpectrumSine(self.w);
        end
        
        function [S,k,m] = IsopycnalSpectrumAtHorizontalAndVerticalWavenumbers(self)
            %% Isopycnal wavenumber spectrum as a function of depth, m^4
            
            [S,k,m] = self.MakeHorizontalAndVerticalWavenumberSpectrumSine(self.eta);
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Variances and energy as a function of vertical wavenumber
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function [S,m] = HorizontalVelocitySpectrumAtVerticalWavenumbers(self)
            %% Horizontal velocity vertical wavenumber spectrum, m^3/s^2
            
            [S,m] = self.MakeVerticalWavenumberSpectrumWithCosineTransform(self.u+sqrt(-1)*self.v,3);
            S = squeeze(mean(mean(S,1),2));
        end
        
        function [S,m] = VerticalVelocitySpectrumAtVerticalWavenumbers(self)
            %% Vertical velocity vertical wavenumber spectrum, m^3/s^2
            
            [S,m] = self.MakeVerticalWavenumberSpectrumWithSineTransform(self.w,3);
            S = squeeze(mean(mean(S,1),2));
        end
        
        function [S,m] = IsopycnalSpectrumAtVerticalWavenumbers(self)
            %% Isopycnal wavenumber vertical spectrum, m^3

            [S,m] = self.MakeVerticalWavenumberSpectrumWithSineTransform(self.eta,3);
            S = squeeze(mean(mean(S,1),2));
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %
        % Interpolation onto Lagrangian particles
        %
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function varargout = InterpolatedFieldAtPosition(self,x,y,z,method,varargin)
            if nargin-5 ~= nargout
                error('You must have the same number of input variables as output variables');
            end
            
            % (x,y) are periodic for the gridded solution
            x_tilde = mod(x,self.Lx);
            y_tilde = mod(y,self.Ly);
            
            dx = self.x(2)-self.x(1);
            x_index = floor(x_tilde/dx);
            dy = self.y(2)-self.y(1);
            y_index = floor(y_tilde/dy);
            
            % Identify the particles along the interpolation boundary
            if strcmp(method,'spline')
                S = 3+1; % cubic spline, plus buffer
            elseif strcmp(method,'linear')
                S = 1+1;
            end
            bp = x_index < S-1 | x_index > self.Nx-S | y_index < S-1 | y_index > self.Ny-S;
            
            % then do the same for particles that along the boundary.
            x_tildeS = mod(x(bp)+S*dx,self.Lx);
            y_tildeS = mod(y(bp)+S*dy,self.Ly);
            
            varargout = cell(1,nargout);
            for i = 1:nargout
                U = varargin{i}; % gridded field
                uinterp = zeros(size(x)); % interpolated value
                uinterp(~bp) = interpn(self.X,self.Y,self.Z,U,x_tilde(~bp),y_tilde(~bp),z(~bp),method);
                if any(bp)
                    uinterp(bp) = interpn(self.X,self.Y,self.Z,circshift(U,[S S 0]),x_tildeS,y_tildeS,z(bp),method);
                end
                varargout{i} = uinterp;
            end
        end
        
        function varargout = InterpolatedFieldAtPositionNewAndShiny(self,x,y,z,method,varargin)
            if nargin-5 ~= nargout
                error('You must have the same number of input variables as output variables');
            end
            
            % (x,y) are periodic for the gridded solution
            x_tilde = mod(x,self.Lx);
            y_tilde = mod(y,self.Ly);
            
            dx = self.x(2)-self.x(1);
            x_index = floor(x_tilde/dx);
            dy = self.y(2)-self.y(1);
            y_index = floor(y_tilde/dy);
            dz = self.z(2)-self.z(1);
            z_index = self.Nz+floor(z/dz)-1;
            
            if length(unique(diff(self.z)))>1
                error('This optimized interpolation does not yet work for uneven z')
            end
            
            % Identify the particles along the interpolation boundary
            if strcmp(method,'spline')
                S = 3+1; % cubic spline, plus buffer
            elseif strcmp(method,'linear')
                S = 1+1;
            end
            
            %             % can't handle particles at the boundary
            %             xrange = mod(((min(x_index)-S):(max(x_index)+S)),self.Nx)+1;
            %             yrange = mod(((min(y_index)-S):(max(y_index)+S)),self.Ny)+1;
            xrange = ((min(x_index)-S):(max(x_index)+S))+1;
            yrange = ((min(y_index)-S):(max(y_index)+S))+1;
            zrange = (max((min(z_index)-S),0):min((max(z_index)+S),self.Nz-1))+1;
            
            varargout = cell(1,nargout);
            for i = 1:nargout
                U = varargin{i}; % gridded field
                u = interpn(self.X(xrange,yrange,zrange),self.Y(xrange,yrange,zrange),self.Z(xrange,yrange,zrange),U(xrange,yrange,zrange),x_tilde,y_tilde,z,method);
                varargout{i} = u;
            end
        end
        
    end
end