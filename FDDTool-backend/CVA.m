function [T2mon,Qmon,Ta,Qa]=CVA(a,n,p,f,X,Xt)
    % 输入变量：
    %   X:   训练数据集。每行是一个观测值，每列是一个变量
    %   Xt:   测试数据。每行是一个观测值，每列是一个变量
    %   a:     置信水平
    %   n:     保留的状态维度
    %   p:     过去观测的长度
    %   f:     未来观测的长度

%%%%%%%%%% TRAINING %%%%%%%%%%

%Construct past and future observation matrices of first training data set
[Yp,Yf]=hankelpf(X,p,f);

%Normalization of past and future matrices
pn = size(Yp,2);

fmean = mean(Yf,2);
fstd = std(Yf,0,2);
pmean = mean(Yp,2);
pstd = std(Yp,0,2);

Yp = (Yp - pmean(:,ones(1,pn)))./pstd(:,ones(1,pn));
Yf = (Yf - fmean(:,ones(1,pn)))./fstd(:,ones(1,pn));

%%
%Obtain Cholesky matrices and Hankel matrix
Rp = chol(Yp*Yp'/(pn-1));            %Past Cholesky matrix
Rf = chol(Yf*Yf'/(pn));              %Future Cholesky matrix
Hfp = Yf*Yp'/pn;                     %Cross-covariance matrix
H = (Rf'\Hfp)/Rp;                    %Hankel matrix

%%
[~,S,V] = svd(H);                   %SVD
S = diag(S);
m = numel(S);
V1 = V(:,1:n);                      %Reduced V matrix
J = V1'/Rp';                        %Transformation matrix of state variables
L = (eye(m)-V1*V1')/Rp';            %Transformation matrix of residuals
z = J * Yp;                         %States of training data
e = L * Yp;                         %Residuals of training data    

T = sum(z.*z);                      %T^2 of training data
Q = sum(e.*e);                      %Q statistic of training data

%%
%Compute kde based control limits
Tp = gkde(T);                            %KDE of T^2
Qp = gkde(Q);                            %KDE of Q statistic
Tf=cumsum([0;diff(Tp.x(:))].*Tp.f(:));   %T^2 Probability 
Qf=cumsum([0;diff(Qp.x(:))].*Qp.f(:));   %Q Probability
Ta = max(Tp.x(Tf<=a));                   %Control limit of T^2
Qa = max(Qp.x(Qf<=a));                   %Control limit of Q statistic

%%

%%%%%%%%%% MONITORING %%%%%%%%%%

%construct past obseravtion matrix of test data
Ypm = hankelpf(Xt,p,f);   

%Normalise past test observation matrix
pn=size(Ypm,2);
Ypmn = (Ypm - pmean(:,ones(1,pn))) ./ pstd(:,ones(1,pn));

%Compute T^2 and Q indicators for monitoring
zk = J*Ypmn;            %States of test data
T2mon = sum(zk.*zk);    %Tsquare of test data
ek = L*Ypmn;            %Residuals of test data
Qmon = sum(ek.*ek);     %Q statistic of test data

end


function [Yp,Yf]=hankelpf(y,p,f)
% HANKELPF  Constructing the past and future Hankel matrices
 
% Inputs:
%   y:  N x ny observed data with N observation points and ny variables.
%   p:  the number of past observations
%   f:  the number of future observations.
% Outputs:
%   Yp: the past Hankel matrix with dimension p*ny x M, M = N - p - f;
%   Yf: the future Hankel matrix with dimension f*ny x M.

if nargin < 3
    f = p;
end

if nargout < 2
    f = 0;
end

[N,ny] = size(y);                     % number of observations
Ip = flipud(hankel(1:p,p:N-f));       % indices of past observations
Yp = reshape(y(Ip,:)',ny*p,[]);       % Hankel observation matrix

if nargout>1
    If = hankel(p+1:p+f,p+f:N);       % indices of future observations
    Yf = reshape(y(If,:)',ny*f,[]);   % Hankel observation matrix
end

end


function p=gkde(x,p)
% GKDE  Gaussian kernel density estimation and update.
% 
% Usage:
% p = gkde(d) returns an estmate of pdf of the given random data d in p,
%             where p.f is the pdf vector estimated at p.x locations, 
%             p.h and p.n are the bandwidth and number of samples used for
%             the estimation. 
% p = gkde(d,p) calculates (p.n=0) or updates (p.n>0) the pdf estimation
%             using locations at p.x, bandwidth p.h and previous estimation
%             p.f. For a fresh estimation, p.f=0. Specify p.hnew if a
%             change of bandwidth is required.
%
% Without any output, gkde(d) or gkde(d,p) will disply the estimated
% (updated) pdf plot.  
%
% Check input and output
error(nargchk(1,2,nargin));
error(nargoutchk(0,1,nargout));

% features of given data
x=x(:);
n=numel(x);

% Default parameters, optimal for Gaussian kernel
if nargin<2
    N=100;
    p.h=median(abs(x-median(x)))*1.5704/(n^0.2);
    dx=p.h*3;
    p.n=0;
    p.x=linspace(min(x)-dx,max(x)+dx,N);
    p.f=zeros(1,N);
    p.xmax=inf;
    p.xmin=-inf;
end

% check the structue
p=checkp(p);

% scale back if update
if p.n>0
    p.f=p.f*p.n;
    dx=mean(diff(p.x));
    xl=max(p.x(1)-min(x)+3*p.h,p.xmin);
    nl=max(0,ceil(xl/dx));
    xh=min(max(x)+p.h*3-p.x(end),p.xmax);
    nh=max(0,ceil(xh/dx));
    p.x=[p.x(1)-nl*dx:dx:p.x(1)-dx p.x p.x(end)+dx:dx:p.x(end)+nh*dx];
    p.f=[zeros(1,nl) p.f zeros(1,nh)];
end
N=numel(p.x);

% Gaussian kernel function
kerf=@(z)exp(-z.*z/2)/sqrt(2*pi);

% density estimation or update
for k=1:N
    t=p.x(k);
    h=min(min(t-p.xmin,p.h),min(p.xmax-t,p.h));
    if h<0
        p.f(k)=0;
        continue
    end
    sx=(t-x)/h;
    sy=(-sx.*sx/2);
    sz=exp(sy);
    ss=kerf((t-x)/h);
    p.f(k)=p.f(k)+sum(kerf((t-x)/h))/h;
end
p.n = p.n + n;
p.f = p.f / p.n;

end

function p=checkp(p)
%check structure p
if ~isstruct(p) || ~all(isfield(p,{'x','f','n','h'}))
    error('p is not a right structure.');
end
error(varchk(eps, inf, p.h, 'Bandwidth, p.h is not positive.'));
if ~isfield(p,'xmax')
    p.xmax=inf;
end
if ~isfield(p,'xmin')
    p.xmin=-inf;
end
idx=p.x>p.xmax | p.x<p.xmin;
p.x(idx)=[];
p.f(idx)=[];
end

function msg=varchk(low,high,n,msg)
% check if variable n is not between low and high, returns msg, otherwise
% empty matrix
if n>=low && n<=high
    msg=[];
end
end