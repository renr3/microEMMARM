# -*- coding: utf-8 -*-
"""
CESSIPy: Civil Engineer Stochastic System Identification for Python
    
Author: Matheus Roman Carini 
Support email: matheuscarini@gmail.com
Site: https://github.com/MatheusCarini/CESSIPy
MIT License

Federal University of Rio Grande do Sul, Porto Alegre, Brazil

Version: 1.1
Date: 20211012
"""

#=============================================================================
import sys
import numpy             as np
import matplotlib.pyplot as plt
import matplotlib        as mpl

from MRPy                import MRPy  
from scipy               import signal
from scipy.optimize      import curve_fit
from matplotlib.gridspec import GridSpec

plt.rcParams["font.family"] = "Times New Roman"
mpl.rcParams['mathtext.fontset'] = 'cm'

#=============================================================================
# Naked Class
#=============================================================================

class auxclass(np.ndarray):
    """
    Create a simple class to improve code readability
    """
   
    def __new__(cls, np_array):

        return np.asarray(np_array).view(cls)

#=============================================================================
# Time-Domain
#=============================================================================
        
def rearrange_data(self,ref):
    """
    Rearrange the l outputs by positioning the r reference outputs in the first
    rows. 
    
    Parameters
    -------
    self : MRPy_like
        Time data MRPy object.          
    ref: tupple, list
        List of reference sensors.
    
    Returns
    -------
    yk : MRPy_like
        MRPy object that contains the reference outputs in the first rows and 
        the attributes r and l.
    ..  l : MRPy attribute
            Number of outputs.
    ..  r : MRPy attribute
            Number of reference outputs.         
    """        
          
    r = len(ref)
    l = self.shape[0]
    
    yk   = MRPy(np.empty((l,self.N)),fs=self.fs)
    yk.r = r
    yk.l = l
    
    yk[:r,:] = self[ref,:]
    yk[r:,:] = np.delete(self, ref, 0)
    
    return yk

#-----------------------------------------------------------------------------    
    
def Toeplitz(self, i):
    """
    Create the block Toeplitz matriz, which gathers the output covariances
    estimates up to 2*i-1 time lags.
    
    Parameters
    -------
    self : MRPy_like        
        MRPy object that contains the time data and the attributes r and l.          
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
        
    Returns
    -------
    T : auxclass_like
        Auxclass object that contains the block Toeplitz matrix and the 
        attributes r, l and i.
    """       
    
    N = self.N - 2*i + 1
    r = self.r
    l = self.l

    Ypref = np.zeros((r*i,N))
    Yf    = np.zeros((l*i,N))
        
    for k in range(i):
        Ypref[k*r:k*r+r,:] = self[:r,k:k+N]
        Yf   [k*l:k*l+l,:] = self[: ,k+i:k+i+N]
        
    Ypref = Ypref/N**0.5
    Yf    = Yf   /N**0.5
        
    T   = auxclass(Yf @ Ypref.T)
    
    T.fs, T.r, T.l, T.i = self.fs, r, l, i

    return T

#-----------------------------------------------------------------------------    
    
def SSI_COV(T, no):
    """
    Covariance-Driven Stochastic Subspace Identification Method
    
    Estimate the eigenfrequencies, damping ratios and mode shapes of the block 
    Toeplitz matrix.
    
    Parameters
    ------- 
    T : auxclass_like
        Auxclass object that contains the block Toeplitz matrix and the 
        attributes SVD, r, l and i. 
    no : int
        State space model order.
        
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.
    V : ndarray
        Mode shapes array as columns.
        
    See also
    ------- 
    Toeplitz, SSI_COV_iterator
    """
    
    l = T.l
    i = T.i       
    U, S, VT = T.SVD
               
    U1 = U[:,:no]
    S1 = np.eye(no)*S[:no]           
    Oi = U1 @ S1**0.5    
    C  = Oi[:l,:]
    
    A  = np.linalg.pinv(Oi[:l*(i-1),:]) @ Oi[l:l*i+1,:]
    Λd, Ψ = np.linalg.eig(A)
    
    λ  =  np.log(Λd)*T.fs
    fn =  np.abs(λ)/(2*np.pi)
    zt = -np.real(λ)/np.abs(λ)                
    V  =  C @ Ψ
    
    return fn, zt, V
 
#-----------------------------------------------------------------------------
    
def SSI_COV_iterator(yk, i, nmin, nmax, incr=2, plot=False):
    """
    Iterate the SSI_COV function for model orders from nmin to nmax and step 
    equal incr.
    
    Estimate the eigenfrequencies, damping ratios and mode shapes using 
    SSI COV algorithm for increasing state space orders.
    
    Parameters
    ------- 
    yk : MRPy_like
        MRPy object returned by rearrange_data function.
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
    nmin : int
        The starting order number of the state space model.
    nmax : int
        The end order number of the state space model.
    incr : int, optional
        Step, spacing between model orders. The default step size is 2.
    plot : bool, optional
        If true, plots the singular values graph of the Toeplitz matrix.
        Default is false.
        
    Returns
    ------- 
    FN : ndarray
        Eigenfrequencies 2D array. Each row originates from the same state
        space model.
    ZT : ndarray
        Damping ratios 2D array. Each row originates from the same state
        space model.      
    VV : ndarray
        Mode shapes 3D array. The first index selects the state space order.
    
    Notes
    ------- 
    The modal parameters of the first nmin state space model are FN[0,:], 
    ZT[0,:] and VV[0,:,:].            
    """
    
    T  = Toeplitz(yk, i)
    T.method = 'SSI COV'
    if plot: plot_singular_values(T)
    T.SVD = np.linalg.svd(T)
    
    n  = np.arange(nmin,nmax+incr,incr)        
    FN = np.zeros((n.shape[0],nmax))
    ZT = np.zeros((n.shape[0],nmax))
    VV = np.zeros((n.shape[0],T.l,nmax),dtype=np.complex_)
    
    for ii, no in np.ndenumerate(n):
        FN[ii,:no], ZT[ii,:no], VV[ii,:,:no] = SSI_COV(T,no) 
        
    return FN, ZT, VV

#-----------------------------------------------------------------------------
    
def projection(yk, i):
    """
    Compute the QR factorization of the Hankel matrix and calculate the
    matrices Piref, Pi1ref and Yii.
    
    Parameters
    ------- 
    yk : MRPy_like
        MRPy object returned by rearrange_data function.  
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
        
    Returns
    -------     
    Pi : auxclass_like
        Auxclass object that contains the projection of the row space of the 
        future outputs into the rows space of the past reference outputs and
        the attributes r, l and i.
    Pi1 : array_like
        Projection array changing the separation between past and future 
        outputs one row below.
    Yii : array_like
        Subset of the block Hankel matrix.
    """
    
    N = yk.N - 2*i + 1
    r = yk.r
    l = yk.l

    Ypref = np.zeros((r*i,N))
    Yf    = np.zeros((l*i,N))
        
    for k in range(i):
        Ypref[k*r:k*r+r,:] = yk[:r,k:k+N]
        Yf   [k*l:k*l+l,:] = yk[: ,k+i:k+i+N]
        
    Ypref = Ypref/N**0.5
    Yf    = Yf   /N**0.5        
    Href  = np.vstack([Ypref,Yf])
    
    R = np.linalg.qr(Href.T, mode='r').T
    
    Pi  = auxclass(R[r*i:,:r*i]        @ np.eye(r*i,N))
    Pi1 =          R[r*i+l:,:r*i+r]    @ np.eye(r*i+r,N)
    Yii =          R[r*i:r*i+l,:r*i+l] @ np.eye(r*i+l,N)
            
    Pi.fs, Pi.r, Pi.l, Pi.i = yk.fs, r, l, i
    
    return Pi, Pi1, Yii

#-----------------------------------------------------------------------------    
    
def SSI_DATA(Pi, Pi1, Yii, no):
    """
    Data-Driven Stochastic Subspace Identification Method
    
    Estimate the eigenfrequencies, damping ratios and mode shapes of the
    Piref, Pi1ref e Yii matrices.
    
    Parameters
    ------- 
    Pi, Pi1, Yii 
        See projection.             
    no : int
        State space model order.
        
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.
    V : ndarray
        Mode shapes array as columns.
    """
       
    U, S, VT = Pi.SVD
                         
    U1 = U[:,:no]
    S1 = np.eye(no)*S[:no]
                
    Oi  = U1 @ S1**0.5
    Oi1 = Oi[:-Pi.l,:]
            
    Xi  = np.linalg.pinv(Oi) @ Pi
    Xi1 = np.linalg.pinv(Oi1) @ Pi1
            
    AC = np.vstack([Xi1,Yii]) @ np.linalg.pinv(Xi) 
    A  = AC[:no,:]
    C  = AC[no:,:]
            
    Λd, Ψ = np.linalg.eig(A)
    
    λ  =  np.log(Λd)*Pi.fs
    fn =  np.abs(λ)/(2*np.pi)
    zt = -np.real(λ)/np.abs(λ)                
    V  =  C @ Ψ
    
    return fn, zt, V    

#-----------------------------------------------------------------------------
        
def SSI_DATA_iterator(yk, i, nmin, nmax, incr=2, plot=False):
    """
    Iterate the SSI_DATA function for model orders from nmin to nmax and step 
    equal incr.
    
    Estimate the eigenfrequencies, damping ratios and mode shapes using 
    SSI DATA algorithm for increasing state space orders.

    Parameters
    ------- 
    yk : MRPy_like
        MRPy object returned by rearrange_data function.  
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
    nmin : int
        The starting order number of the state space model.
    nmax : int
        The end order number of the state space model.
    incr : int, optional
        Step, spacing between model orders. The default step size is 2.
    plot : bool, optional
        If true, plots the singular values graph of the Pi matrix.
        Default is false.
        
    Returns
    -------  
    FN : ndarray
        Eigenfrequencies 2D array. Each row originates from the same state
        space model.
    ZT : ndarray
        Damping ratios 2D array. Each row originates from the same state
        space model.      
    VV : ndarray
        Mode shapes 3D array. The first index selects the state space order.
    
    Notes
    ------- 
    The modal parameters of the first nmin state space model are FN[0,:], 
    ZT[0,:] and VV[0,:,:].            
    """
    
    Pi, Pi1, Yii = projection(yk, i)
    Pi.method = 'SSI DATA'
    if plot: plot_singular_values(Pi)        
    Pi.SVD = np.linalg.svd(Pi)
        
    n  = np.arange(nmin,nmax+incr,incr)        
    FN = np.zeros((n.shape[0],nmax))
    ZT = np.zeros((n.shape[0],nmax))
    VV = np.zeros((n.shape[0],Pi.l,nmax),dtype=np.complex_)
        
    for ii, no in np.ndenumerate(n):
        
        FN[ii,:no],ZT[ii,:no],VV[ii,:,:no] = SSI_DATA(Pi,Pi1,Yii,no) 
        
    return FN, ZT, VV

#-----------------------------------------------------------------------------
    
def Fast_SSI(yk, i, nmin, nmax, incr=2, plot=False, based='COV'):  
    """
    Estimate the eigenfrequencies, damping ratios and mode shapes using Fast
    Subspace-Based System Identification algorithm 2 from [1] for increasing 
    state space orders.
    
    Parameters
    ------- 
    yk : MRPy_like
        MRPy object returned by rearrange_data function.
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
    nmin : int
        The starting order number of the state space model.
    nmax : int
        The end order number of the state space model.
    incr : int, optional
        Step, spacing between model orders. The default step size is 2.
    plot : bool, optional
        If true, plots the singular values graph. Default is false.
    based : string, optinal
        SSI based method. If 'COV', it uses the covariance-driven SSI. If 
        'DATA', it uses the data-driven SSI. Default is 'COV'.     
        
    Returns
    ------- 
    FN : ndarray
        Eigenfrequencies 2D array. Each row originates from the same state
        space model.
    ZT : ndarray
        Damping ratios 2D array. Each row originates from the same state
        space model.      
    VV : ndarray
        Mode shapes 3D array. The first index selects the state space order.
    
    Notes
    ------- 
    The modal parameters of the first nmin state space model are FN[0,:], 
    ZT[0,:] and VV[0,:,:].    

    Reference
    ----------
    .. [1] Döhler M; Mevel L. Fast Multi-Order Computation of System 
           Matrices in Subspace-Based System Identification. Control 
           Engineering Practice, Elsevier, 2012, 20 (9), pp.882-894. 
           10.1016/j.conengprac.2012.05.005. hal-00724068     
    """
    
    if based.lower() == 'cov':
        
        T  = Toeplitz(yk, i)
        T.method = 'SSI COV'
        if plot: plot_singular_values(T)
        U, S, VT = np.linalg.svd(T)
                          
        U1 = U[:,:nmax]
        S1 = np.eye(nmax)*S[:nmax]           
        Oi = U1 @ S1**0.5     

    
    elif based.lower() == 'data':
    
        Pi, Pi1, Yii = projection(yk, i)
        Pi.method = 'SSI DATA'
        if plot: plot_singular_values(Pi)        
        U, S, VT = np.linalg.svd(Pi)
                                 
        U1 = U[:,:nmax]
        S1 = np.eye(nmax)*S[:nmax]           
        Oi = U1 @ S1**0.5 
            
    else:
        sys.exit('based method must be COV or DATA')       
    
    l = yk.l

    Oiu = Oi[:l*(i-1),:]
    Oid = Oi[l:l*i+1 ,:]    
    C  = Oi[:l,:] 
    
    Q, R = np.linalg.qr(Oiu)
    St = Q.T @ Oid
    
    n  = np.arange(nmin,nmax+incr,incr) 
    FN = np.zeros((n.shape[0],nmax))
    ZT = np.zeros((n.shape[0],nmax))
    VV = np.zeros((n.shape[0],l,nmax),dtype=np.complex_)
    
    for ii, no in np.ndenumerate(n):
        A = np.linalg.inv(R[:no,:no]) @ St[:no,:no]
        Cj = C[:,:no]
    
        Λd, Ψ = np.linalg.eig(A)
        
        λ  =  np.log(Λd)*yk.fs
        
        FN[ii,:no] =  np.abs(λ)/(2*np.pi)
        ZT[ii,:no] = -np.real(λ)/np.abs(λ)  
              
        VV[ii,:,:no]  =  Cj @ Ψ
        
    return FN, ZT, VV

#-----------------------------------------------------------------------------
        
def IV(T, no):
    """
    Instrumental Variable Method

    Estimate the eigenfrequencies, damping ratios and mode shapes of the block 
    Toeplitz matrix.
    
    Parameters
    ------- 
    T : auxclass_like
        Auxclass object that contains the block Toeplitz matrix and the 
        attributes SVD, r, l and i. 
    no : int
        State space model order.
        
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.
    V : ndarray
        Mode shapes array as columns.
        
    See also
    ------- 
    Toeplitz
    """
    
    r = T.r
    l = T.l
    
    αb = np.linalg.lstsq(T[:,-no*r:], 
                        -T[:,-(no+1)*r:-no*r], rcond=None)[0]
    
    Apcomp = np.zeros((no*r,no*r))
    Apcomp[:-r,r:] += np.eye((no-1)*r)
    for kk in range(no):
        Apcomp[-r:,r*kk:r*(kk+1)] -= αb.T[:,r*(no-kk)-r:r*(no-kk)]
    
    Λd, Ψ = np.linalg.eig(Apcomp)
    
    λ  =  np.log(Λd)*T.fs
    fn =  np.abs(λ)/(2*np.pi)
    zt = -np.real(λ)/np.abs(λ)                

    Gmref = (Ψ[:r,:]).T
    Γmref = np.zeros((no*r,no*r),dtype=np.complex_)
    
    for ii in range(no):
        Γmref[:,ii*r:(ii+1)*r] = np.diag(Λd**(no-ii-1)) @ Gmref
        
    V = T[:l,-no*r:] @ np.linalg.inv(Γmref)
    
    return fn, zt, V

#-----------------------------------------------------------------------------
        
def IV_iterator(yk, i, nmin, nmax, incr=2, plot=False):
    """
    Iterate the IV function for model orders from nmin to nmax and step equal 
    incr.
    
    Estimate the eigenfrequencies, damping ratios and mode shapes using IV 
    algorithm for increasing state space orders.

    Parameters
    ------- 
    yk : MRPy_like
        MRPy object returned by rearrange_data function.  
    i : int
        Number of time lags used to calculate the covariances length. 
        Note that they are estimated up to 2*i-1 time lags.
    nmin : int
        The starting order number of the state space model.
    nmax : int
        The end order number of the state space model.
    incr : int, optional
        Step, spacing between model orders. The default step size is 2.
    plot : bool, optional
        If true, plots the singular values graph of the Toeplitz matrix.
        Default is false.
        
    Returns
    -------  
    FN : ndarray
        Eigenfrequencies 2D array. Each row originates from the same state
        space model.
    ZT : ndarray
        Damping ratios 2D array. Each row originates from the same state
        space model.      
    VV : ndarray
        Mode shapes 3D array. The first index selects the state space order.
    
    Notes
    ------- 
    The relation between ARMA order p and state space order n is n = p * r.
    The modal parameters of the first nmin state space model are FN[0,:], 
    ZT[0,:] and VV[0,:,:].            
    """

    T  = Toeplitz(yk,i)
    T.method = 'IV'
    if plot: plot_singular_values(T)        
    
    n  = np.arange(nmin,nmax+incr,incr)        
    FN = np.zeros((n.shape[0],nmax*T.r))
    ZT = np.zeros((n.shape[0],nmax*T.r))
    VV = np.zeros((n.shape[0],T.l,nmax*T.r),dtype=np.complex_)
    
    for ii, no in np.ndenumerate(n):
        FN[ii,:no*T.r], ZT[ii,:no*T.r], VV[ii,:,:no*T.r] = IV(T,no) 
        
    return FN, ZT, VV

#-----------------------------------------------------------------------------    
    
def stabilization_diagram(FN, ZT, VV, 
                         tol = np.array(([0.01,0, 100],
                                         [0.05,0,0.05],
                                         [0.10,0,   1])), 
                         plot={'typeForStabilizationDiagram': 'False', 'fontSize': 15, 'fontName':'Times New Roman', 'figSizeStabilization': (5,2), 'dpi': 150}, 
                         PSD = None, verbose=False):
    """
    Compute the stable poles and plot the stabilization diagram
    
    Parameters
    -------     
    FN, ZT, VV
        Modal parameters returned by SSI_COV_Iterator, SSI_DATA_Iterator and
        IV_Iterator functions.
    tol : ndarray, optional
        Array of stabilization criteria.
        Rows: frequencies, damping ratios and MAC values respectively.
        Columns: percentage tolerance, minimum and maximum values respectively.
        Default is:
        [0.01,0,100 ] Δf = 1%; fmin = 0 Hz; fmax = 100 Hz
        [0.05,0,0.05] Δζ = 5%; ζmin = 0%;   ζmax = 5%
        [0.10,0,1   ] MAC >= (1 - 0.10) = 0.90     
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForStabilizationDiagram': 'False', 'fontSize': 15, 'fontName':'Times New Roman', 'figSizeStabilization': (5,2), 'dpi': 150}
        In which:
            'typeForStabilizationDiagram' is str, which may assume the following values:
                If 'StabilizationOnly', plot only the stabilization diagram
                If 'StabilizationPSD', plot the PSD beneath the stabilization diagram
                If 'False', don't plot anything
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSizeStabilization' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure    
    PSD: a PSD object that is returned by .SDM function, optional. Only mandatory when 'typeForStabilizationDiagram'='StabilizationPSD'.
    verbose: bool, optional
        If true, intermediate messages are plotted in this function, to better track what is happening.
    
    Returns
    -------   
    stb : array_like
        Boolean array that contains True for stable poles (those in which both frequency, damping and mode shapes are stable). Each row originates 
        from the same state space model.
    
    Notes
    ------- 
    First stb index refers to model order. For example, the last stable poles
    row stb[-1,:] originates from nmax model order.
    """
    
    nmin = np.count_nonzero(FN, axis=1)[0]
    nmax = np.count_nonzero(FN, axis=1)[-1]
    incr = (nmax-nmin)//(FN.shape[0]-1)
    n    = np.arange(nmin,nmax+incr,incr)
    stb  = np.full(FN.shape, False)
    stbf = np.full(FN.shape, False)
    stbz = np.full(FN.shape, False)
    
    for ii in range(1,n.shape[0]): 
        
        no = n[ii]; ia = ii - 1
        na = n[ia]         
        
        # Frequencies
        
        b1 = (FN[ii,:no] >= tol[0,1]) & (FN[ii,:no] <= tol[0,2]) #EMM-ARM (19/08/22): Select all eigenfrequencies within the desired eigenfrequency specified in the tol interval.    
        dif = FN[ia,:na] - FN[ii,:no].reshape(-1,1) #EMM-ARM (19/08/22): Compute the differences between eigenfrequencies of the current model order and the previous model order
        ind = np.abs(dif).argmin(axis=1) #EMM-ARM (19/08/22): for each eigenfrequency of the current model order, check to what eigenfrequency of the previous model order it was closest to
        res = np.diagonal(dif[:,ind]) #EMM-ARM (19/08/22): constructs an array containing the lowest difference of each eigenfrequency of the current model order to an eigenfrequency of the last model ORDER
        b1 = (np.abs(res/FN[ii,:no]) < tol[0,0]) & b1 #EMM-ARM (19/08/22): while also selecting already the eigenfrequencies on the range of interest (as made in the first definition of b1), this line will also select only the eigenfrequencies that depart a maximum of tol[0,0] from an eigenfrequency of the previous model order

        #EMM-ARM (19/08/22): In the original version of CESSIPy, an eigenfrequency of a given model order was considered stable if it didn't depart more from any eigenfrequency of the previous model order than the maximum estipulated in the tolerance vector. In order words, the comparation is only done considering the imediately previous model, and no implementation of stability level, such as in KOMA, exists. But based on Peeters PhD thesis, this is the standard approach
        if verbose == True:
            print("###########")
            print("Current model order: ",str(no))
            print("Get to know what FN[ia,:na] is:")
            print(FN[ia,:na])
            print("Get to know what  FN[ii,:no].reshape(-1,1) is:")
            print( FN[ii,:no].reshape(-1,1) )
            print("Get to know what dif is:")
            print(dif)
            print("Get to know what ind is:")
            print(ind)
            print("Get to know what res is:")
            print(res)
            print("Get to know what np.abs(res/FN[ii,:no] is:")
            print(np.abs(res/FN[ii,:no]))   
        
        # Damping ratios
        
        b2 = (ZT[ii,:no] >= tol[1,1]) & (ZT[ii,:no] <= tol[1,2])
        dif = ZT[ia,:na] - ZT[ii,:no].reshape(-1,1)
        res = np.diagonal(dif[:,ind])
        b2 = (np.abs(res/ZT[ii,:no]) < tol[1,0]) & b2 & b1      
        
        # MAC
               
        MCv = MAC(VV[ia,:,:na],VV[ii,:,:no])           
        res = np.abs(np.diag(MCv[ind,:]))                       
        b3 = (res > 1 - tol[2,0]) & b2          
        
        stbf[ii,:no] = b1
        stbz[ii,:no] = b2
        stb [ii,:no] = b3

    #Initiate plot parameters
    titleText = {'fontname':plot['fontName'],'size':plot['fontSize']}
    axisTitleText = {'fontname':plot['fontName'],'size':plot['fontSize']}
    ticksText = {'fontname':plot['fontName'],'size':plot['fontSize']-2}
    legendText = {'family'  :plot['fontName'],'size':plot['fontSize']-2}    

    if plot['typeForStabilizationDiagram']=='StabilizationOnly':  
        #Plot stabilization diagram
        plt.figure(figsize=plot['figSizeStabilization'], dpi=plot['dpi']); 
        for ii in range(n.shape[0]): 
            #EMM-ARM (19/08/22): This function iterates through each model order.
            #EMM-ARM (19/08/22): This exists so null elements in the matrices (those with index > model order) are not plotted.                
            yi = n[ii]*np.ones(n[ii])  
            ko = plt.scatter(FN[ii,:n[ii]],yi,s=2,c='k')
            go = plt.scatter(FN[ii,:n[ii]][stbf[ii,:n[ii]]],
                             yi[stbf[ii,:n[ii]]],s=4,c='g')
            bo = plt.scatter(FN[ii,:n[ii]][stbz[ii,:n[ii]]],
                             yi[stbz[ii,:n[ii]]],s=4,c='b')
            ro = plt.scatter(FN[ii,:n[ii]][stb [ii,:n[ii]]],
                             yi[stb [ii,:n[ii]]],s=8,c='r')
        #Define plot labels and texts
        plt.xlim((0,tol[0,2]))
        plt.ylim((0,n[-1]))
        plt.xticks(**ticksText)
        plt.yticks(n,**ticksText)
        plt.xlabel('f (Hz)',**axisTitleText)
        plt.ylabel('Model Order',**axisTitleText)
        plt.suptitle(' Stabilization Diagram',**titleText)
        plt.legend([ko, go, bo, ro], 
                  ["New pole", 
                   "Stable frequency",
                   "Stable frequency and damping",
                   "Stable frequency, damping and mode shape"], 
                   loc='lower right', prop=legendText)
        plt.tight_layout(rect=[0, 0, 1, 0.97])

    elif plot['typeForStabilizationDiagram']=='StabilizationPSD':          
        # Crete figure and the first axis
        fig, ax_left = plt.subplots(figsize=plot['figSizeStabilization'], dpi=plot['dpi']);       

        #Plot first the PSD using the secondary axis     
        ax_right = ax_left.twinx()       
        psdLine = ax_right.semilogy(PSD.f[1:],np.abs(PSD[0, 0, 1:]),color="gray",label = "Power spectral density")
        #Take care of y-axis limit of the secondary axis
        if (plot['ylimForPSD'][0] != None) or (plot['ylimForPSD'][1] != None): #If some limit was specified
            if (plot['ylimForPSD'][0] != None) and (plot['ylimForPSD'][0] != None): 
                #Both were specified
                ax_right.set_ylim([plot['ylimForPSD'][0],plot['ylimForPSD'][1]])
            elif (plot['ylimForPSD'][0] != None):
                #Only the lower bound was specified
                ax_right.set_ylim([plot['ylimForPSD'][0],max(np.abs(G[0, 0, 1:]))])
            else:
                #Only the upper bound was specified
                ax_right.set_ylim(min(np.abs(G[0, 0, 1:])),plot['ylimForPSD'][1])
        plt.sca(ax_right)
        plt.ylabel('Amplitude (g²/Hz)',**axisTitleText)     
        plt.xlim((0,tol[0,2]))
        plt.yticks(**ticksText)
        
        #Plot stabilization diagram in the left axis (main axis)
        for ii in range(n.shape[0]): 
            #EMM-ARM (19/08/22): This function iterates through each model order.
            #EMM-ARM (19/08/22): This exists so null elements in the matrices (those with index > model order) are not plotted.
            # 
            if ii==1:                
                yi = n[ii]*np.ones(n[ii])  
                ko = ax_left.scatter(FN[ii,:n[ii]],yi,s=2,c='k',label = "New pole")
                go = ax_left.scatter(FN[ii,:n[ii]][stbf[ii,:n[ii]]],
                                yi[stbf[ii,:n[ii]]],s=4,c='g',label = "Stable frequency")
                bo = ax_left.scatter(FN[ii,:n[ii]][stbz[ii,:n[ii]]],
                                yi[stbz[ii,:n[ii]]],s=4,c='b',label = "Stable frequency and damping")
                ro = ax_left.scatter(FN[ii,:n[ii]][stb [ii,:n[ii]]],
                                yi[stb [ii,:n[ii]]],s=8,c='r',label = "Stable frequency, damping and mode shape")
            else:
                yi = n[ii]*np.ones(n[ii])  
                ko = ax_left.scatter(FN[ii,:n[ii]],yi,s=2,c='k')
                go = ax_left.scatter(FN[ii,:n[ii]][stbf[ii,:n[ii]]],
                                yi[stbf[ii,:n[ii]]],s=4,c='g')
                bo = ax_left.scatter(FN[ii,:n[ii]][stbz[ii,:n[ii]]],
                                yi[stbz[ii,:n[ii]]],s=4,c='b')
                ro = ax_left.scatter(FN[ii,:n[ii]][stb [ii,:n[ii]]],
                                yi[stb [ii,:n[ii]]],s=8,c='r')
        #Define plot labels and texts
        ax_left.set_xlim((0,tol[0,2]))
        ax_left.set_ylim((0,n[-1]))
        plt.sca(ax_left)
        plt.xticks(**ticksText)
        plt.yticks(n,**ticksText)
        plt.xlabel('f (Hz)',**axisTitleText)
        plt.ylabel('Model Order',**axisTitleText)
        fig.legend(loc='lower right', prop=legendText, bbox_to_anchor=(1,0), bbox_transform=ax_left.transAxes)
        plt.tight_layout(rect=[0, 0, 1, 0.97])
        plt.suptitle(' Stabilization Diagram',**titleText)

    return stb

#-----------------------------------------------------------------------------
        
def stable_modes(FN, ZT, V, stb, tol=0.01, spo=6, verbose=False):
    """
    Gather close stable poles into the same mode.
       
    Parameters
    -------   
    FN, ZT, V
        Modal parameters returned by SSI_COV_Iterator, SSI_DATA_Iterator and
        IV_Iterator functions.
    stb : array_like
        Boolean array returned by stabilization_diagram function.
    tol : float
        Frequency tolerance. Close poles are gathered into a single mode.
        Default is 0.01 = 1%.
    spo : int
        Minimum number of stable poles in order to assign the mode as stable.
        Default is 6.
    verbose: bool, optional
        If true, intermediate messages are plotted in this function, to better track what is happening.
    
    Returns
    ------- 
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.
    v : ndarray
        Mode shapes array as columns.
    numStablePoles: ndarray
        Number of poles associated to each stable pole.

    Notes
    -------
    The same modal model is represented by two stable poles.
    """

    FN = FN[stb]
    ZT = ZT[stb]      
    VV = V[0,:,stb[0]].T
    
    for j in range(stb.shape[0]):
        VV = np.hstack((VV,V[j,:,stb[j]].T))
    
    fsi = np.argsort(FN) #EMM-ARM (19/08/22): fsi stores the original indices of FN in the ascending order considering the values of FN elements. For examples: fsi = np.argsort([3 6 2]) would return fsi = [2 0 1]

        
    #EMM-ARM (19/08/22): These are the reordered matrices in ascending order.
    FNs, ZTs, VVs = FN[fsi], ZT[fsi], VV[:,fsi]
    
    #EMM-ARM (19/08/22): These variables will store the final values of stable poles
    fn, zt, v = np.array([]), np.array([]), V[0,:,stb[0]].T 

    #EMM-ARM (19/08/22): New variable to store the number of stable poles associated to each frequency
    numStablePoles= np.array([])
    
    k = 0  
    
    for i in range(len(FN)):
        
        b0 = (FNs > (1-tol)*FNs[k]) & (FNs < (1+tol)*FNs[k]) #EMM-ARM (19/08/22): Select only the values of FNs that lie within the tolerance (1-tol) and (1+tol) from FNs[k]. b0 will be a vector contain True in the positions that meet this criteria, and false in those that don't meet this criteria.

        if b0.sum() >= spo: #EMM-ARM (19/08/22): If the current selection has more than spo table poles (this may be verified by summing all True elements in b0), compute the representative value of the stable pole
            
            fn = np.append(fn,(FNs[b0]).mean())
            zt = np.append(zt,(ZTs[b0]).mean())
            
            mv = np.argmax(np.abs(VVs[:,b0]),axis=0)[0]
            nv = np.mean(VVs[:,b0]/VVs[mv,b0],axis=1).reshape(-1,1)
            v  = np.hstack((v,nv))

            numStablePoles = np.append(numStablePoles,b0.sum())

        #EMM-ARM (19/08/22): Because FNs is ordered, then the next pole for verification will necessarily be equal to the index bo.sum(). For example, if FNs=[2 2.02 2.05 2.1 28.5 28.7 28 30.65 30.7 30.8], then the first iteration, for k=0, will verify FNs(0) = 30.8 as stable pole. b0 will necessariy be a vector like b0 = [True True True False False False False False False False], i.e., after the first False, all other values will necessarily be False too, because they are lower than the first False and, thus, more far away than the first False element from the pole under verification.
        #The original code performed an oversum on the updated value of k, because it also considered eventual values higher than the pole under verification, which could skip values! It is better to sum on k just the values which are True due to (FNs > (1-tol)*FNs[k]), so the next value to serve for verification will always be the first value that was too small to not be verified before!

        #EMM-ARM (19/08/22): Original code: #k += b0.sum() 
        #EMM-ARM (19/08/22): Updated code:
        k += ((FNs < (1+tol)*FNs[k]) & (FNs >= FNs[k])).sum() 
        
        if k > len(FN)-1: break

    if verbose == True:
        print("=================================================================================")
        print("RESULTS FROM SSI METHOD")
        print("Frequencies identified (in an ordered way):")
        eigenfrequenciesIndices = np.flip(np.argsort(numStablePoles))
        if fn.size == 0:
            print('No sufficiently large frequency clusters could be identified') 
        else:
            for i, j in enumerate(np.take_along_axis(fn, eigenfrequenciesIndices, 0)[0:3]): print('#{:d}: {:.3f} Hz'.format(i+1,j)) 
        print("Damping ratios:")
        if zt.size == 0:
            print('No sufficiently large damping clusters could be identified') 
        else:
            for i, j in enumerate(np.take_along_axis(zt, eigenfrequenciesIndices, 0)[0:3]): print('#{:d}: {:.3f} %'.format(i+1,100*j))
        print("Number of stable poles:")
        if numStablePoles.size == 0:
            print('No sufficiently large clusters could be identified') 
        else:
            for i, j in enumerate(np.take_along_axis(numStablePoles, eigenfrequenciesIndices, 0)[0:3]): print('#{:d}: {:d}'.format(i+1,int(j)))
        #TODO: Implement showing mode shapes
        print("END OF RESULTS FROM SSI METHOD")
        print("=================================================================================")     

    return fn, zt, v, numStablePoles

#-----------------------------------------------------------------------------
    
def plot_singular_values(T, figsize=(14, 4), nmx=40):
    """
    Compute and plot the singular values.
     
    Parameters
    -------   
    T : auxclass_like
        Auxclass object that contains the matrix and the attribute method.
    figsize : tuple, optional
        Graph size. Default is (14,4).
    nmx : int, optional
        Number of singular values displayed in the graph.    
    """
    
    a_for = {'size':16}
    l_for = {'size':16}
    
    S   = np.linalg.svd(T, compute_uv=False)[:nmx]
    idx = np.argmin(S[1:]/S[:-1])
 
    fig, ax = plt.subplots(1, 3,figsize=figsize)
    fig.suptitle('%s Singular Values' %(T.method), **a_for) 
    
    label = ['\n(a) singular values',
             'Model Order\n(b) normalized by the first',
             '\n(c) normalized by the previous']
       
    ax[0].plot(np.arange(1,nmx+1),S,'bo',ms=4)
    ax[0].set_ylabel('Singular Values', **l_for)
    ax[0].set_ylim(bottom=0)
    
    ax[1].semilogy(np.arange(1,nmx+1),S/S[0],'b',idx+1,(S/S[0])[idx],'ro')
    ax[1].annotate('%.0f' %(idx+1),(idx+1.5,(S/S[0])[idx]),**l_for)
    
    ax[2].semilogy(np.arange(1,nmx+1), np.hstack((1,S[1:]/S[:-1])),'b',
                 idx+1,(S[1:]/S[:-1])[idx-1],'ro')
    ax[2].annotate('%.0f' %(idx+1),(idx+1.5,(S[1:]/S[:-1])[idx-1]),**l_for)
                     
    for i in range(3): 
        ax[i].set_xticks(np.linspace(0,nmx,nmx//2+1))
        ax[i].tick_params(labelsize=12)
        ax[i].set_xlim((0,nmx))
        ax[i].set_xlabel(label[i], **l_for)

    fig.tight_layout(rect=[0, 0, 1, 0.97])
    
    return

#=============================================================================
# Frequency-Domain
#=============================================================================  
    
def SDM(self, nperseg=None, plot={'typeForPSD': 'False', 'frequencyBand': [0, 0], 'fontSize': 15, 'fontName':'Times New Roman', 'figSize': (5,2), 'dpi': 150}, window='hann', nfft=None, 
        ):
    """      
    Estimate the spectral density matrix.
    
    The signals are divided into segments with nperseg values to obtain 
    smoothed estimates.  

    Parameters
    -------          
    self : MRPy_like
        MRPy object that contains the time data.
    nperseg : int, optional
        Length of each segment. Default is the signal length.
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForPSD': 'False', 'ylimForPSD': [1e-8,None], 'fontSize': 15, 'fontName':'Times New Roman', 'figSize': (5,2), 'dpi': 150}
        In which:
            'typeForPSD' is str, which may assume the following values:
                If 'PSD+phase', plot both PSD and phase angle frequency spectral estimates. Adapted to multiple outputs, which produces multiple cross PSDs
                If 'Single_PSD', plot only PSD frequency spectral estimates. Proper when single output is available, producing a single autoPSD
                If 'False', don't plot anything
            'frequencyBand' is a list specifying the frequency band to be used when ploting, i.e., the frequency limits of the x axis of the PSD
            'ylimForPSD' is a list specifying the lower limit and the upper limit for the y-axis scale. If some limit is specified as 'None', the default value based on the series data will be used
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSize' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure
    fontSize: scalar, option #Editted EMM-ARM
        Specify the font size of the plot.
    window : string, optional
        Desired window to use. Default is 'hann'.
    nfft : int, optional
        Length of the FFT used, if a zero padded FFT is desired. If None, the 
        FFT length is nperseg. Defaults to None.
    figsize : tuple, optional
        Graph size. Default is (12,12)
        
    Returns
    -------   
    PSD : auxclass
        Auxclass object that contains the spectral densities and the attributes
        f and nperseg.
    
    See also
    -------              
    scipy.signal.csd 
    """                
    
    if nperseg is None: nperseg = self.N
    if nfft is None: nfft = nperseg
    if nfft < nperseg:
        raise ValueError('nfft must be greater than or equal to nperseg.')
    
    G = np.empty((self.NX, self.NX, nfft//2+1), dtype=np.complex_)
    
    for i in range(self.NX):
        for j in range(self.NX):
            f, G[i,j] = signal.csd(self[i,:], self[j,:], self.fs, 
                window=window, nperseg=nperseg, nfft=nfft)           
                         
    if plot['typeForPSD']=='PSD+phase':

        l_for = {'fontname':plot['fontName'],'size':plot['fontSize']}        
        
        if plot['frequencyBand'][1]==0: 
            #This means no frequency limits were set, so the default setting of using the maximum possible frequency is used
            axis_f = [0, f[-1]]
        else:
            #The frequency limits have been informed by the user
            axis_f = [plot['frequencyBand'][0],plot['frequencyBand'][1]]
        
        #axis_G = [10**7*np.min(np.abs(G[:,:,1:])),1.2*np.max(np.abs(G))]
        
        n = G.shape[0]   # number of double-rows
        m = G.shape[1]   # number of columns
        H = 3            # relação gráfica amplitude pela fase            
        t = 0.9          # 1-t == top space 
        b = 0.1          # bottom space      (both in figure coordinates)            
        w = 0.05         # side spacing
        μ = 0.1          # minor spacing
        Μ = 0.2          # major spacing
        
        spa  = (t-b)/(n*(1+μ+1/H)+(n-1)*Μ)
        offb = spa*(μ+1/H)
        offt = spa*(1+μ)
        hsp1 = Μ+μ+1/H
        hsp2 = (Μ+μ+1)*H
        
        gso = GridSpec(n,m, bottom=b+offb, top=t, hspace=hsp1, wspace=w)  
        gse = GridSpec(n,m, bottom=b, top=t-offt, hspace=hsp2, wspace=w)         
        
        fig = plt.figure(figsize=plot['figSize'])
        
        for i in range(n*m):        
            
            ax1 = fig.add_subplot(gso[i])
            ax2 = fig.add_subplot(gse[i])
            
            ax1.semilogy(f[1:],np.abs(G[i//m, i%m, 1:]),color='blue')
            ax1.set_xlim(axis_f)
            #ax1.set_ylim(axis_G) 
            ax1.set_xticklabels([])
            ax1.set_title(r'$\hat G_y[{:d},{:d}]$'.format(i//m+1,i%m+1),
                                                                  fontsize=plot['fontSize']) 
            
            if i%m != 0:
                ax1.set_yticklabels([])
            else:
                ax1.set_ylabel('Amplitude (g²/Hz)',**l_for)
                         
            ax2.plot(f,np.angle(G[i//m, i%m]))
            ax2.set_xlim(axis_f)
            ax2.set_ylim([-4,4])
            
            if i%m != 0:
                ax2.set_yticklabels([])
            else:
                ax2.set_ylabel('Phase (rad)',**l_for)
            
            if i//m == n-1:
                ax2.set_xlabel('f (Hz)',**l_for)
            else:
                ax2.set_xticklabels([])
                
            ax1.tick_params(labelsize=plot['fontSize'])
            ax2.tick_params(labelsize=plot['fontSize'])
                        
        plt.show()

    elif plot['typeForPSD']=='Single_PSD': #Editted by EMM-ARM (19/08/2022)      
        
        if plot['frequencyBand'][1]==0: 
            #This means no frequency limits were set, so the default setting of using the maximum possible frequency is used
            axis_f = [0, f[-1]]
        else:
            #The frequency limits have been informed by the user
            axis_f = [plot['frequencyBand'][0],plot['frequencyBand'][1]]
            
        fig = plt.figure(figsize=plot['figSize'], dpi=plot['dpi'])
        plt.semilogy(f[1:],np.abs(G[0, 0, 1:]))
        plt.xlim(axis_f)

        #Take care of y-axis limit
        if (plot['ylimForPSD'][0] != None) or (plot['ylimForPSD'][1] != None): #If some limit was specified
            if (plot['ylimForPSD'][0] != None) and (plot['ylimForPSD'][0] != None): 
                #Both were specified
                plt.ylim([plot['ylimForPSD'][0],plot['ylimForPSD'][1]])
            elif (plot['ylimForPSD'][0] != None):
                #Only the lower bound was specified
                plt.ylim([plot['ylimForPSD'][0],max(np.abs(G[0, 0, 1:]))])
            else:
                #Only the upper bound was specified
                plt.ylim(min(np.abs(G[0, 0, 1:])),plot['ylimForPSD'][1])

        plt.xlabel('f (Hz)',size=plot['fontSize'], fontname=plot['fontName'])
        plt.ylabel('Amplitude (g²/Hz)',size=plot['fontSize'], fontname=plot['fontName'])            
        plt.show()
     
    PSD                          = auxclass(G)
    PSD.f, PSD.nperseg, PSD.nfft = f, nperseg, nfft
        
    return PSD

#-----------------------------------------------------------------------------

def ANPSD_from_SDM(PSD, plot=False, mode='interactive'):
    """      
    Compute the Averaged Normalized Power Spectral Density from the spectral
    density matrix.

    Parameters
    -------       
    PSD : auxclass_like
        Auxclass object returned by the SDM function.
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForEFDD': 'False', 'ylimForEFDD': [None,1.1], 'fontSize': 15, 'fontName':'Times New Roman', 'figSize': (5,2), 'dpi': 150}
        The peak(s) will always be plotted together with the curve
        In which:
            'typeForEFDD' is str, which may assume the following values:
                If 'All', plot all normalized NPSD and the average NPSD, if there are more than one DOF in the acceleration time series
                If 'only_ANPSD', plot only the average NPSD
                If 'False', don't plot anything
            'ylimForEFDD' is a list specifying the lower limit and the upper limit for the y-axis scale. If some limit is specified as 'None', the default value based on the series data will be used
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSize' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure
    mode : string, optional
        Mode of the peak selection. If 'interactive', the user should select  
        the peaks with the mouse. If 'batch', the peaks must be informed in
        the attribute pki. Default is 'interactive'.
    
    Returns
    -------   
    PSD : auxclass_like
        Auxclass object that contains the attributes ANPSD and pki.
        
    Batch mode
    ------- 
    Auxclass object must have the attribute pki.
    pki : list
        Indexes of the peak frequencies.       
    """ 
    
    try:
        G = PSD.diagonal()
        f = PSD.f
    
    except AttributeError:
        sys.exit('PSD must be computed by the SDM function')
    
    NPSD  = np.real((G / G.sum(axis=0)).T)
    ANPSD = np.real(NPSD.sum(axis=0)) / G.shape[1]
    
    if mode.lower() == 'interactive':
        
        class SnaptoCursor:
            """
            Provides data cursor
            The crosshair snaps to the closest point
            Adapted from matplotlib gallery
            https://matplotlib.org/3.2.2/gallery/misc/cursor_demo_sgskip.html
            """
    
            def __init__(self, ax, x, y):
                self.ax  = ax
                self.txt = ax.text(0.8, 0.95, '', transform=ax.transAxes)
                self.lx, self.ly = ax.axhline(color='k'), ax.axvline(color='k')  
                self.x,  self.y  = x, y
        
            def mouse_move(self, event):
                if not event.inaxes: return
                x, y = event.xdata, event.ydata
                indx = np.argmin((f-x)**2+1E4*(ANPSD-y)**2)
                x, y = self.x[indx], self.y[indx]
                self.lx.set_ydata(y), self.ly.set_xdata(x)
                self.txt.set_text('f = %1.2f Hz'%x)
                self.ax.figure.canvas.draw()

        fig, ax = plt.subplots(figsize=(12,5))
        plt.semilogy(f,np.abs(ANPSD))
        snap_cursor = SnaptoCursor(ax, f, np.abs(ANPSD))
        plt.gcf().canvas.mpl_connect('motion_notify_event', 
               snap_cursor.mouse_move)           
        plt.gcf().canvas.mpl_connect
        plt.xlim([0, f[-1]])
        plt.xlabel('Frequency (Hz)')
        plt.ylabel('ANPSD ((m/s²)²/Hz)')
        #plt.ylim([1E6*ANPSD.min(),1.6*ANPSD.max()])        

        plt.title('Click the left mouse button to select the peaks\n'
                  'Press middle mouse button to finalize')
        
        plt.text(.7,0.01,
                 'Peaking: left button\n'
                 'Undo: right button\n'
                 'Finalize: middle button',transform=plt.gca().transAxes)

        plt.tight_layout(rect=[0, 0.03, 1, 0.97])
        
        pnt = np.array(plt.ginput(n=-1,timeout=0))
        fn = np.zeros(len(pnt))
        for ii in range(len(pnt)):
            fn[ii]  =  f[np.argmin((f-pnt[ii,0])**2+1E4*(ANPSD-pnt[ii,1])**2)]
        pki = np.argmin(np.abs(f-fn.reshape(-1,1)),axis=1)    
        
        plt.close()
                    
    elif mode.lower() == 'batch':
        
        try:
            pki = PSD.pki
            
        except AttributeError:
            sys.exit('PSD must have pki attribute in batch mode')
                    
    else:
        sys.exit('mode must be interactive or batch')
    
    if plot['typeForEFDD']=='All': #Editted EMM-ARM 22/08/2022
        plt.figure(figsize=plot['figSize'], dpi=plot['dpi']) 
        plt.subplot(211)
        plt.title('NPSD')
        for ii, row in enumerate(NPSD):
            plt.semilogy(f,row,label=ii+1)            
        plt.legend(loc = 'lower right')
        plt.xlim([0, f[-1]])
        plt.xlabel('Frequency (Hz)', size=plot['fontSize'], fontname=plot['fontName'])
        plt.ylabel('Normalized amplitude (-)', size=plot['fontSize'], fontname=plot['fontName'])
        #plt.ylim([1E5*NPSD.min(),1.6*NPSD.max()])
        
        plt.subplot(212)
        plt.title('ANPSD')
        plt.semilogy(f,np.abs(ANPSD))
        plt.xlim([0, f[-1]])
        plt.xlabel('Frequency (Hz)', size=plot['fontSize'], fontname=plot['fontName'])
        plt.ylabel('Normalized amplitude (-)', size=plot['fontSize'], fontname=plot['fontName'])
        #plt.ylim([1E5*ANPSD.min(),1.6*ANPSD.max()])
        plt.tight_layout()
        plt.plot(f[pki], ANPSD[pki], "x")

        for i in pki:
            plt.annotate('Ref. peak: {:.3f} Hz'.format(f[i]),
                         (f[i],ANPSD[i]*1.08), ha='center')            
        plt.show()

    elif plot['typeForEFDD']=='only_ANPSD': #Editted EMM-ARM 22/08/2022
        plt.figure(figsize=plot['figSize'], dpi=plot['dpi']) 
        plt.semilogy(f,np.abs(ANPSD))
        plt.xlim([0, f[-1]])
        
        #Take care of y-axis limit
        if (plot['ylimForEFDD'][0] != None) or (plot['ylimForEFDD'][1] != None): #If some limit was specified
            if (plot['ylimForEFDD'][0] != None) and (plot['ylimForEFDD'][0] != None): 
                #Both were specified
                plt.ylim([plot['ylimForEFDD'][0],plot['ylimForEFDD'][1]])
            elif (plot['ylimForEFDD'][0] != None):
                #Only the lower bound was specified
                plt.ylim([plot['ylimForEFDD'][0],max(np.abs(ANPSD))])
            else:
                #Only the upper bound was specified
                plt.ylim(min(np.abs(ANPSD)),plot['ylimForEFDD'][1])

        plt.xlabel('Frequency (Hz)', size=plot['fontSize'], fontname=plot['fontName'])
        plt.ylabel('Normalized amplitude (-)', size=plot['fontSize'], fontname=plot['fontName'])
        #plt.ylim([1E5*ANPSD.min(),1.6*ANPSD.max()])
        plt.plot(f[pki], ANPSD[pki], "x")

        for i in pki:
            plt.annotate('Ref. peak: {:.3f} Hz'.format(f[i]),
                         (f[i]*1.05,ANPSD[i]*.95), ha='left', size=0.75*plot['fontSize'])            
        plt.show()
           
    PSD.ANPSD  = ANPSD
    PSD.pki    = pki
        
    return PSD
 
#-----------------------------------------------------------------------------
    
def coherence(self, PSD=None, nperseg=None, plot=False):
    """      
    Compute the coherence matrix.
    
    Parameters
    -------       
    self : MRPy_like
        MRPy object that contains the time data.
    PSD : auxclass_like, optional
        Auxclass object returned by the SDM function.
    nperseg : int, optional
        Length of each segment. Default is the signal length.
    plot : bool, optional
        If true, plots the spectral matrix. Default is false.

    Returns
    -------   
    γ : auxclass_like
        Auxclass object that contains the coherence functions and the attribute
        f. 
    
    See also
    -------  
    scipy.signal.coherence
    """     
    if nperseg is None:
        try:
            nperseg = PSD.nperseg
        except AttributeError:
            sys.exit('nperseg must be a parameter or a PSD attribute')      
    
    γ = np.empty((self.NX,self.NX,nperseg//2+1))
    
    for i in range(self.NX):
        for j in range(self.NX):
            f, γ[i,j] = signal.coherence(self[i,:], self[j,:],
                 self.fs, nperseg=nperseg)                     

    γ   = auxclass(np.real(γ))
    γ.f = f
            
    if plot:
        
        a_for = {'fontname':'Times New Roman','size':14} 
        l_for = {'fontname':'Times New Roman','size':12}        
        t_for = {'family':'Times New Roman','size':10}
        
        NX = self.NX
        
        plt.figure(figsize=(8,8))
        
        for i in range(NX):
            for j in range(NX):
                ax = plt.subplot(NX,NX,i*NX+j+1)
                ax.plot(f,γ[i,j])
                if PSD != None: ax.plot(f[PSD.pki],γ[i,j][PSD.pki],'ro')
                ax.set_title(r'$\gamma^2_{{{:d},{:d}}}$'
                             .format(i+1,j+1),**a_for)
                ax.set_xlim([0,f[-1]])
                ax.set_ylim([0, 1.05])
                
                if j == 0:
                    #ax.set_yticklabels(np.linspace(0,1,6),**t_for)
                    plt.yticks(**t_for)
                    ax.set_ylabel('Coeherence',**l_for)
                else:
                    ax.set_yticklabels([])
                                   
                if i == NX - 1:
                    plt.xticks(**t_for)
                    ax.set_xlabel('f (Hz)',**l_for)
                else:
                    ax.set_xticklabels([])
          
        plt.tight_layout()
    
    return γ

#-----------------------------------------------------------------------------

def BFD(self, PSD, plot=False, mode='interactive', verbose=False):
    """      
    Basic Frequency Domain Method / Peak Picking Method

    Estimate the eigenfrequencies, damping ratios and mode shapes of the 
    spectral matrix.

    Damping is estimated by the half-power bandwitdh method and by fitting the 
    theoretical acceleration response power spectral density of a single-DOF 
    system with random applied force excitation.

    Parameters
    -------       
    self : MRPy_like
        MRPy object that contains the time data.
    PSD : auxclass_like
        Auxclass object that contains the spectral densities. Returned by the
        SDM function.
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForBFD': 'False', 'fontSize': 15, 'fontName':'Times New Roman', 'figSizeBFD': (5,2), 'dpi': 150}
        The peak(s) will always be plotted together with the curve
        In which:
            'typeForBFD' is bool, which may assume the following values:
                If True, plot results
                If False, don't plot anything
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSize' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure
    mode : string, optional.
        Input method. If 'interactive', the user should select the inputs with 
        the mouse. If 'batch', the inputs must be informed in the attributes
        fint, MGi and pki of the PSD object. Default is 'interactive'.
    verbose: bool, optional.
        Defines if verbose mode is on, so to print the results of the identification metho
    
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : list
        Damping ratios array. Half-power bandwitdh method estimate zt[0]. 
        Curve fitting estimate zt[1].
    V : ndarray
        Mode shapes array as columns.
    PSD : auxclass_like
        Auxclass object that contains the attributes ANPSD, pki, MGi e fint.
        
    Batch mode
    -------  
    The PSD object must have the attributes fint, MGi e pki.
    fint : array      
        Initial and final frequencies used to curve fitting. 
    MGi : integer array
        Autospectral indexes used to damping and mode shape estimates.
    pki : integer array
        Eigenfrequencies indexes.    

    Notes
    -------  
    Call the SDM e ANPSD_from_SDM functions before calling this function.
    """                
    try:
        f, pki = PSD.f, PSD.pki
        G      = np.abs(PSD.diagonal().T)  # autospectral
    except AttributeError:
        sys.exit('PSD must have the attributes f, nperseg and pki')   
        
    #-------------------------------------------------------------------
           
    if mode.lower() == 'interactive':
        
        print('Select the reference autospectral density')

        global MGi, NX
        MGi, NX = [], self.NX 

        def onclick_select(event):  # identify the subplot selected by the user
            global MGi, NX
            for i in range(NX):
                if event.inaxes == ax[0,i]:
                    MGi = np.array(np.append(MGi,i),dtype='int')
        
        for i, j in enumerate(pki):            
            fig, ax = plt.subplots(1, self.NX,figsize=(10, 4),sharey=True,squeeze=False)
            plt.suptitle('Left click on the reference autospectral density\n'
                         'use to damping and mode shape estimates')
                            
            for k in range(self.NX): 
                ax[0,k].semilogy(f,G[k]) 
                ax[0,k].semilogy(f[j],G[k,j],'ro')
                ax[0,k].set_xlim((0,f[-1]))
                ax[0,k].annotate('{:.2E}'.format(G[k,j]),(f[j],G[k,j]*1.05))
            
            ax[0,0].set_ylabel('Amplitude ((m/s²)²/Hz)')
            ax[0,k//2].set_xlabel('Frequency (Hz)')
            plt.tight_layout(rect=[0, 0.03, 1, 0.92])    
            fig.canvas.mpl_connect('button_press_event', onclick_select)
            plt.ginput(n=1,timeout=30)
            plt.close()        
        
        fint = np.zeros(2*len(pki))
        
        for i,(j,k) in enumerate(zip(pki,MGi)):
            plt.figure(figsize=(10,6))
            plt.title('Left click on the extremes of the interval ' 
                      'to curve fitting')
            plt.semilogy(f,G[k])
            plt.semilogy(f[j],G[k][j],'ro')   
            plt.annotate('{:.3f} Hz'.format(f[j]),(f[j],G[k][j]*1.15), ha='center')     
            #plt.xlabel(r'$f_n$ = {:.3f} Hz'.format(f[j]))
            plt.xlabel('Frequency (Hz)')
            plt.ylabel('Amplitude ((m/s²)²/Hz)')
            plt.xlim([0,f[-1]])
            
            pnt = np.array(plt.ginput(n=2,timeout=0))[:,0]
            
            id1 = np.argmin(np.abs(f-pnt.reshape(-1,1)),axis=1)
            fint[2*i:2*i+2] = f[id1]
            
            plt.close()     
            
        PSD.fint = fint
        PSD.MGi  = MGi
       
    elif mode.lower() == 'batch':
        try:
            MGi  = PSD.MGi
            fint = PSD.fint
        except AttributeError:
            sys.exit('PSD must have the attributes MGi and fint in batch mode')   
    
    else:
        sys.exit('mode must be interactive or batch')   

    #-------------------------------------------------------------------
    def Sy(f,c1,c2,fn,ζ):

        return c1*np.abs(2*np.pi*f**2/(1-(f/fn)**2+2j*ζ*(f/fn)))**2 + c2       
    #-------------------------------------------------------------------       
                                                                                        
    ζhp = np.zeros((len(pki)))
    ζft = np.zeros((len(pki)))
    P   = np.zeros((len(pki),4))
    
    idx = np.argmin(np.abs(f-fint.reshape(-1,1)),axis=1)
    
    if plot['typeForBFD'] != False: #Editted EMM-ARM 22/08/2022
        fig, ax = plt.subplots(1,len(MGi),figsize=(len(MGi)*plot['figSizeBFD'][0], plot['figSizeBFD'][1]),squeeze=False, dpi=plot['dpi']) #Editted EMM-ARM 22/08/2022

    for i, (j, k, ii, si) in enumerate(zip(MGi,pki,idx[::2],idx[1::2])):
        
        mG = G[j,k]
        fa = np.interp( mG/2, G[j,ii:k+1],f[ii:k+1])
        fb = np.interp(-mG/2,-G[j, k:si ],f[ k:si ])
        f0 = f[k]
        
        ζhp[i] = (fb**2-fa**2)/(4*f[k]**2)    # half-power
        
        Pmin = (0     , 0    , fa, 0.000)     # lower bounds
        P0   = (0     , 0    , f0, 0.010)     # initial guesses 
        Pmax = (mG/1E2,mG/1E3, fb, 0.05 )     # upper bounds   
        
        P[i,:], _ = curve_fit(Sy,f[ii:si],G[j,ii:si],
                                         p0=P0,bounds=(Pmin, Pmax))
        ζft[i] = P[i,3]
    
        if plot['typeForBFD'] != False: #Editted EMM-ARM 22/08/2022:
            ax[0,i].semilogy(f[ii:si],G[j,ii:si])
            ax[0,i].semilogy(np.linspace(f[ii],f[si],100),
                         Sy(np.linspace(f[ii],f[si],100),*P[i,:]),'k:') 
            ax[0,i].plot(f0,mG,'rx')
            ax[0,i].plot([fa,fb],[mG/2,mG/2],'ro')
            ax[0,i].annotate('{:.3f} Hz'.format(f0),(f0,G[j,k]*1.05), 
                                                                  ha='center',size=0.75*plot['fontSize'])
            ax[0,i].annotate('{:.3f} Hz'.format(fa),(fa,  mG/2*1.05), 
                                                                  ha='right',size=0.75*plot['fontSize'])
            ax[0,i].annotate('{:.3f} Hz'.format(fb),(fb,  mG/2*1.05), 
                                                                  ha='left',size=0.75*plot['fontSize']) 
            ax[0,i].text(.99, .99, r'$\xi_{{hp}}$ = {:.2f}%'.format(ζhp[i]*100) 
                +'\n'+ r'$\xi_{{ft}}$ = {:.2f}%'.format(ζft[i]*100), 
                horizontalalignment='right',verticalalignment='top', 
                transform=ax[0,i].transAxes,fontsize=11)
            
    if plot['typeForBFD'] != False: #Editted EMM-ARM 22/08/2022: 
        ax[0,0].set_ylabel('Amplitude (g²/Hz)', size=plot['fontSize'], fontname=plot['fontName'])
        ax[0,i//2].set_xlabel('Frequency (Hz)', size=plot['fontSize'], fontname=plot['fontName'])   
        ax[0,i].legend(['Spectral density','Curve fitted',
          'Eigenfrequency','Half-power frequencies'], loc='lower right', fontsize=plot['fontSize'])
        #fig.tight_layout()
            
    fn = f[pki]
    V  = PSD[MGi,:,pki]/PSD[MGi,MGi,pki].reshape(-1,1)            
    V  = np.abs(V)*(1-2*((np.angle(V)>np.pi/2)+(np.angle(V)<-np.pi/2)))

    if verbose == True:
        print("=================================================================================")
        print("RESULTS FROM BFD METHOD")
        print("Frequencies identified:")
        if fn.size == 0:
            print('No frequencies could be identified') 
        else:
            for i, j in enumerate(fn): print('#{:d}: {:.3f} Hz'.format(i+1,j)) 
        print("Damping ratios identified with the Half-Power Method:")
        if ζhp.size == 0:
            print('No damping ratios with half-power method could be identified') 
        else:
            for i, j in enumerate(ζhp): print('#{:d}: {:.3f} %'.format(i+1,100*j))
        print("Damping ratios identified with the Fitting Method:")
        if ζft.size == 0:
            print('No damping ratios with fitting method could be identified') 
        else:
            for i, j in enumerate(ζft): print('#{:d}: {:.3f} %'.format(i+1,100*j)) 
        #TODO: Implement showing mode shapes
        print("END OF RESULTS FROM BFD METHOD")
        print("=================================================================================")            
    
    return fn, ζhp, ζft, V.T, PSD
   
#-----------------------------------------------------------------------------
    
def EFDD(self, PSD, plot='False', mode='interactive', verbose='off'):
    """      
    Enhanced Frequency-Domain Decomposition method
       
    Estimate the eigenfrequencies, damping ratios and mode shapes of the 
    spectral matrix.

    Parameters
    -------       
    self : MRPy_like
        MRPy object that contains the time data.
    PSD : auxclass_like
        Auxclass object that contains the spectral densities. Returned by the
        SDM function.
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForEFDD': 'Autocorrelation-SVD', 'fontSize': 15, 'fontName':'Times New Roman', 'figSizeEFDD': (5,2), 'dpi': 150}
        The peak(s) will always be plotted together with the curve
        In which:
            'typeForBFD' is a str, which may assume the following values:
                If 'Autocorrelation', plot only the autocorrelation function
                If 'Autocorrelation-SVD', plot the autocorrelation function and the SVD graph
                If 'Autocorrelation-SVD-Phase', plot the autocorrelation function, SVD, and Phase
                If 'False', don't plot anything
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSizeEFDD' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure
    mode : string, optional.
        Input method. If 'interactive', the user should select the inputs with 
        the mouse. If 'batch', the inputs must be informed in the attributes
        fint, MGi and pki. Default is 'interactive'.
    verbose: string, optional.
        Defines if verbose mode is on, so to print the results of the identification method
    
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : list
        Damping ratios array.
    V : ndarray
        Mode shapes array as columns.
    PSD : auxclass_like
        Auxclass object that contains the attributes pki, svi, fint and tint.
           
    Batch mode
    -------  
    The PSD object must have the attributes pki, svi, fint and tint.
    pki : list
        Eigenfrequencies indexes.    
    svi : list
        Singular values indexes. 
    fint : array
        Initial and final frequencies of the interval used to compute the
        autocorrelation function.
    tint : array
        Initial and final time interval used to fit the theoretical 
        autocorrelation function.
    """ 
    G, f, nperseg, nfft = PSD, PSD.f, PSD.nperseg, PSD.nfft
    
    U, S, VH = np.zeros_like(G), np.zeros_like(G), np.zeros_like(G)
    
    USV = np.zeros((self.NX,len(f)))
    
    for i in range(len(f)):
        U[:,:,i],S[:,:,i],VH[:,:,i] = np.linalg.svd(G[:,:,i])    
        
    for i in range(self.NX):
        for j in range(len(f)):
            USV[i,j] = np.abs(U[i,:,j] * S[i,i,j] @ VH[:,i,j])  
        
    #----------------------------------------
    
    if mode.lower() == 'interactive':
               
        plt.figure(figsize=plot['figSizeEFDD'])
        
        for i in range(self.NX):
            plt.semilogy(f[1:],USV[i,1:])
        
        print('Peak selection')
        
        plt.text(.7,0.01,
                 'Peaking: left button\n'
                 'Undo: right button\n'
                 'Finalize: middle button',transform=plt.gca().transAxes)

        plt.title('Peak selection')
        plt.legend(["1st","2nd","3rd","4th"])
        plt.xlabel('Frequency (Hz)')
        plt.ylabel('Singular Values of the Spectral Matrix')
        plt.xlim([0, f[-1]])
        plt.tight_layout()

        pnt = plt.ginput(n=-1,timeout=0)          
        x   = np.array(pnt)[:,0]
        pki = np.abs(f-x.reshape(-1,1)).argmin(axis=1)  
        y   = np.array(pnt)[:,1]
        svi = np.abs(USV[:,pki]-y).argmin(axis=0)   
        
        plt.close()
                
        #----------------------------------------
        
        fint = np.zeros(2*len(pki))
    
        for i, (j, k) in enumerate(zip(svi,pki)):
            
            MACv = MAC(U[:,j,[k]],U[:,j,:])[0]
            
            fig = plt.figure(figsize=(10, 6)) 
            
            try:
                imin = np.abs(np.max(f[:k][MACv[:k] < 0.8])-f).argmin() + 1
            except ValueError:
                imin = 0
            try:
                imax = np.abs(np.min(f[k:][MACv[k:] < 0.8])-f).argmin()
            except ValueError:
                imax = -1            
            
            gs = GridSpec(2, 1, height_ratios = [4, 1]) 
            
            ax0 = plt.subplot(gs[0])
            ax0.semilogy(f[1:],USV[j,1:])  
            ax0.semilogy(f[imin:imax], USV[j][imin:imax])
            ax0.semilogy(f[k],USV[j,k],'ro') 
            ax0.legend(["Singular values of spectral matrix",
                        "MAC > 0.8","Eigenfrequency"])
            ax0.set_xlim([0,f[-1]])    
            ax0.set_ylabel('Singular value spectral density')
            ax0.set_xticklabels([])
            ax0.set_title('Select the extremes of the interval')
            
            ax1 = plt.subplot(gs[1])
            ax1.plot(f,MACv)   
            ax1.set_xlim([0,f[-1]]) 
            ax1.set_xlabel('Frequency (Hz)')
            ax1.set_ylabel('MAC')
            
            gs.tight_layout(fig)
            
            pnt = np.array(plt.ginput(n=2,timeout=0))[:,0]
            
            id1 = np.argmin(np.abs(f-pnt.reshape(-1,1)),axis=1)
            fint[2*i:2*i+2] = f[id1]
            
            plt.close()    

        PSD.pki, PSD.svi, PSD.fint = pki, svi, fint
        
    #----------------------------------------

    elif mode.lower() == 'batch':
        try:
            pki  = PSD.pki
            svi  = PSD.svi
            fint = PSD.fint
        except AttributeError:
            sys.exit('PSD must have the attributes pki, svi and fint')   
    
    #----------------------------------------
    
    else:
        sys.exit('mode must be interactive or batch')           
            
    #----------------------------------------

    idx = np.argmin(np.abs(f-fint.reshape(-1,1)),axis=1)
    
    FSD  = np.zeros((len(pki),S.shape[2]))
    MACv = np.zeros((len(pki),S.shape[2]))

    for i, (j, k, ii, si) in enumerate(zip(svi,pki,idx[::2],idx[1::2])):
        FSD[i,ii:si] = USV[j,ii:si] 
        MACv[i] = MAC(U[:,j,[k]],U[:,j,:])[0]
    
    R   = np.fft.irfft(FSD)          # autocorrelation
    env = np.abs(np.fft.ifft(FSD))   # positive envelope of autocorrelation
    
    R   = R  /np.max(np.abs(R),axis=1).reshape(-1,1)   # normalizing by max
    env = env/np.max(      env,axis=1).reshape(-1,1)   # abs value
    
    t   = np.linspace(0,self.Td*nfft/self.N,  R.shape[1])   # time series
    te  = np.linspace(0,self.Td*nfft/self.N,env.shape[1])
  
    win = (nperseg-np.arange(0,nperseg))/nperseg       # triangular window
    
    R   =   R[:,:nperseg]/win        # divide by windows to remove bias
    env = env[:,:nperseg]/win
    
    fn, zt, PSD = fit_autc(PSD, t, te, R, env, mode, plot)     
    
    #----------------------------------------          
        
    if plot['typeForEFDD'] == 'Autocorrelation-SVD-Phase': #Editted EMM-ARM 22/08/2022
        
        fig = plt.figure(figsize=plot['figSizeEFDD'], dpi=plot['dpi'])
        gs = GridSpec(2, 1, height_ratios = [3, 1]) 
        
        ax0 = plt.subplot(gs[0])     
        
        leg = ['1st singular value','2nd singular value','3rd singular value']
        
        for ii in range(G.shape[0]):
            ax0.semilogy(f[1:],USV[ii,1:],label=leg[ii])
            
        for i, (ii, si) in enumerate(zip(idx[::2],idx[1::2])):
            ax0.semilogy(f[ii:si],np.abs(FSD[i,ii:si]),'r',label=(i//1)*"_"+'Mode')
        
        ax0.legend(fontsize=plot['fontSize'])
        ax0.plot(f[pki], USV[svi,pki], "x")
        
        for jj,kk in zip(pki,svi):
            ax0.annotate('{:.3f} Hz'.format(f[jj]),
                         (f[jj],USV[kk,jj]*1.25), ha='center')
            
        ax0.set_xlim([0,f[-1]])  
        ax0.set_xticklabels([])
        ax0.set_ylabel('Amplitude (g²/Hz)',size=plot['fontSize'])
        ax0.set_title('Singular values of the spectral matrix',size=plot['fontSize'])
        
        leg = ['1st mode','2nd mode','3rd mode','4th mode','5th mode','6th mode']
        
        ax1 = plt.subplot(gs[1])
        for i, (ii, si) in enumerate(zip(idx[::2],idx[1::2])):
            ax1.plot(f[ii:si],MACv[i,ii:si],label=leg[i])  #(f[ii:si],MACv[i,ii:si],'r')
        
        ax1.legend(fontsize=plot['fontSize'])
        ax1.set_xlim([0,f[-1]])
        ax1.set_xlabel('Frequency (Hz)',size=plot['fontSize'])
        ax1.set_ylabel('MAC',size=plot['fontSize'])
        
        gs.tight_layout(fig)

    elif plot['typeForEFDD'] == 'Autocorrelation-SVD': #Editted EMM-ARM 22/08/2022
        
        fig = plt.figure(figsize=plot['figSizeEFDD'], dpi=plot['dpi'])
        
        leg = ['1st singular value','2nd singular value','3rd singular value']
        
        for ii in range(G.shape[0]):
            plt.semilogy(f[1:],USV[ii,1:],label=leg[ii])
            
        for i, (ii, si) in enumerate(zip(idx[::2],idx[1::2])):
            plt.semilogy(f[ii:si],np.abs(FSD[i,ii:si]),'r',label=(i//1)*"_"+'Mode')
        
        plt.legend(fontsize=plot['fontSize'])
        plt.plot(f[pki], USV[svi,pki], "x")
        
        for jj,kk in zip(pki,svi):
            plt.annotate('{:.3f} Hz'.format(f[jj]),
                         (f[jj],USV[kk,jj]*1.25), ha='center', size=0.75*plot['fontSize'])
            
        plt.xlim([0,f[-1]])  
        plt.ylabel('Amplitude (g²/Hz)',size=plot['fontSize'])
        plt.title('Singular values of the spectral matrix',size=plot['fontSize'])
        
    #------------------------------------------
    
    V = U[:,svi,pki]

    if verbose == True:
        print("=================================================================================")
        print("RESULTS FROM EFDD METHOD")
        print("Frequencies identified:")
        if fn.size == 0:
            print('No frequencies could be identified') 
        else:
            for i, j in enumerate(fn): print('#{:d}: {:.3f} Hz'.format(i+1,j)) 
        print("Damping ratios:")
        if zt.size == 0:
            print('No damping ratios could be identified') 
        else:
            for i, j in enumerate(zt): print('#{:d}: {:.3f} %'.format(i+1,100*j))
        #TODO: Implement showing mode shapes
        print("END OF RESULTS FROM BFD METHOD")
        print("=================================================================================")          
     
    return fn, zt, V, PSD

#----------------------------------------------------------------------------- 
    
def fit_autc(PSD, t, te, R, env, mode='interactive', plot='False', plotScale=1):
    """
    Fit the theorical autocorrelation function.
    
    Estimate eigenfrequency and damping.
    
    Parameters
    -------       
    PSD : auxclass_like
        Auxclass object that contains the attributes f and pki.
    t : ndarray
        Time data array.
    te : ndarray
        Envelope time data array.
    R : ndarray
        Autocorrelation functions array.
    env : ndarray
        Envelope of autocorrelation functions array.
    mode : string, optional.
        Input method. If 'interactive', the user should select the inputs with 
        the mouse. If 'batch', the inputs must be informed in the attributes
        fint, MGi and pki. Default is 'interactive'.
    plot : dictionary, optional #Editted EMM-ARM
        It has the following format:
            plot={'typeForEFDD': 'Autocorrelation-SVD', 'fontSize': 15, 'fontName':'Times New Roman', 'figSizeEFDD': (5,2), 'dpi': 150}
        The peak(s) will always be plotted together with the curve
        In which:
            'typeForBFD' is a str, which may assume the following values:
                If 'Autocorrelation', 'Autocorrelation-SVD', or 'Autocorrelation-SVD-Phase', plot the autocorrelation function
                If 'False', don't plot anything
            'fontSize' is a scalar and specifies the base font size of the plot
            'fontName' is a str and specifies the font type of the plot
            'figSizeEFDD' is a tuple (width, height) and specifies the size of the figure
            'dpi' is a scalar and specifies the DPI of the figure
    
    Returns
    -------    
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.
    PSD : auxclass_like
        Auxclass object that contains the attribute tint.

    Batch mode
    -------  
    The PSD object must have the attributes f, pki and tint.
    f : Array
        Frequencies array.
    pki : integer array
        Eigenfrequencies indexes.    
    tint : array
        Initial and final time interval used to fit the theoretical 
        autocorrelation function. 
    """    

    #--------------------------------------------------
    def envelope(t, Xp, η):
        
        return Xp*np.exp(-η*t)
    
    def decay(t, Xp, η, fn):

        ωn = 2*np.pi*fn
        ζ  = η/ωn
        ωd = ωn * (1-ζ**2)**.5
        
        return Xp*np.exp(-η*t)*np.cos(ωd*t)
    
    #--------------------------------------------------
    
    if mode.lower() == 'interactive':    

        idx = np.zeros(2*len(PSD.pki),dtype=int)
            
        for ii in range(len(PSD.pki)):  
            plt.figure(figsize=(6*plotScale,4*plotScale))
            plt.plot(te[:len(te)//4],env[ii][:len(te)//4],'bo')
            plt.xlim([0,te[len(te)//4]])
            plt.xlabel('Time (s)')
            plt.ylabel('Normalized Autocorrelation')
            plt.title('Click the extremes of the interval')
            plt.tight_layout()       
            
            pnt = np.array(plt.ginput(n=2,timeout=0))[:,0]
            idx[2*ii:2*ii+2] = np.argmin(np.abs(te-pnt.reshape(-1,1)),axis=1)
            
            plt.close()
            
        PSD.tint = te[idx]
    
    #----------------------------------------
    
    elif mode.lower() == 'batch':
        try:
            tint = PSD.tint            
        except AttributeError:
            sys.exit('PSD must have the attribute tint in batch mode')   
         
        idx = np.argmin(np.abs(te-tint.reshape(-1,1)),axis=1)
        
    #----------------------------------------
    
    else:
        sys.exit('mode should be interactive or batch')           
            
    #----------------------------------------

    P   =  np.zeros((len(PSD.pki), 2))
    Q   =  np.zeros((len(PSD.pki), 1))
       
    for i, (j, k) in enumerate(zip(idx[::2],idx[1::2])):

        X0 =  1.00                   # initial amplitude value  
        ζ0 =  0.01                   # initial damping value  
        fn =  PSD.f[PSD.pki[i]]      # initial natural frequency
        η0 =  2*np.pi*fn*ζ0              
        
        Pmin = (1.00*X0, 0*η0)       # lower bounds
        P0   = (     X0,   η0)       # initial guesses
        Pmax = (1.25*X0, 5*η0)       # upper bounds   

        P[i,:], cv = curve_fit(envelope, te[j:k], env[i,j:k],       # fit for
                                        p0=P0, bounds=(Pmin, Pmax)) # X and η         
                
        Qmin = (0.97*fn)             # lower bounds
        Q0   = (     fn)             # initial guesses
        Qmax = (1.03*fn)             # upper bounds   
        
        Q[i,:], cv = curve_fit(lambda x, fn: decay(x,*P[i,:], fn),  
             t[2*j:2*k], R[i,2*j:2*k], p0=Q0, bounds=(Qmin, Qmax)) # fit for fn

    #--------------------------------------------------

    fn = Q[:,0]
    zt = P[:,1]/(2*np.pi*fn)

    #--------------------------------------------------
    
    if plot['typeForEFDD'] != False:
        
        tf = np.linspace(0,t[-1],len(t)*100)

        fig, ax = plt.subplots(1, len(PSD.pki), figsize=plot['figSizeEFDD'], dpi=plot['dpi'],
                               sharey=True,squeeze=False)   
        
        for i, (j, k) in enumerate(zip(idx[::2],idx[1::2])):
            ax[0,i].plot(t[2*j:2*k],R[i,2*j:2*k],'bo')
            ax[0,i].plot(tf,decay(tf, *P[i,:], *Q[i,:])) #fitted curve
            ax[0,i].set_xlim(0,t[2*k])
            
            ax[0,i].text(.99, .99, r'$f_n$ = {:.3f} Hz'.format(fn[i]) 
                +'\n'+ r'$\xi$ = {:.2f}%'.format(zt[i]*100), 
                horizontalalignment='right',verticalalignment='top', 
                transform=ax[0,i].transAxes,fontsize=11)

           
        ax[0,i//2].set_xlabel("Time (s)", size=plot['fontSize'])
        ax[0,0].set_ylabel("Normalized Autocorrelation", size=plot['fontSize'])
        fig.suptitle('Autocorrelation functions', size=plot['fontSize'])     
        fig.tight_layout(rect=[0, 0.03, 1, 0.97])    
    
    
    return fn, zt, PSD

#=============================================================================
# Other functions: MAC and mode shapes graph
#=============================================================================  
    
def MAC(Ψi, Ψj, plot=False):
    """
    Compute the Modal Assurance Criterion [2] from the columns of the  Ψi and 
    Ψj matrices.
    
    Parameters
    -------     
    Ψi, Ψj : array_like
        2D array that contains the mode shapes as columns.
    plot : bool, optional
        If true, plots the MACs graph. Default is false.        

    Returns
    -------     
    MAC : array_like
    
    Reference
    ----------
    .. [2] Allemang, R. J.; Brown, D. L. "A correlation coefficient for 
           modal vector analysis", In: 1st International Modal Analysis
           Conference, p. 110-116, 1982.
    """
    
    MOMij =         Ψi.T @ np.conj(Ψj)
    MOMii = np.diag(Ψi.T @ np.conj(Ψi))
    MOMjj = np.diag(Ψj.T @ np.conj(Ψj))
    
    MAC   = np.abs(MOMij)**2 / np.outer(MOMii,MOMjj)
    
    if plot:
        plt.figure()
        plt.pcolormesh(np.real(MAC), cmap='Blues', vmin=0, vmax=1, 
                       edgecolors='k', linewidth=.5)
        cb = plt.colorbar()
        cb.ax.set_title('MAC')
        plt.xticks(np.arange(.5,MAC.shape[1]  ,1),
                   np.arange( 1,MAC.shape[1]+1,1))
        plt.yticks(np.arange(.5,MAC.shape[0]  ,1),
                   np.arange( 1,MAC.shape[0]+1,1))
        plt.gca().invert_yaxis()
        plt.gca().xaxis.tick_top()
        plt.tight_layout()
    
    return np.real(MAC)

#-----------------------------------------------------------------------------
        
def plot_1dshapes(fn, zt, vv, title, X, ref=False, fix=False):
    """  
    Plot one-dimensional mode shapes    
    
    Parameters
    -------   
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.         
    vv : ndarray
        Array that contains the mode shapes as columns.
    title : string
        Graph title.
    X : ndarray
        Positions of the l sensors.
    ref : tuple, list, optional
        List of reference sensors.
    fix : list, optional
        Adds zero value to the mode shape at informed positions. For example,
        if fix=[0,L], adds zero at position X = 0 and X = L. Default is false.
    """        
    a_for = {'fontname':'Times New Roman','size':14}
    l_for = {'fontname':'Times New Roman','size':12}
    t_for = {'fontname':'Times New Roman','size':10}
    
    if ref != False:  
        X  = np.hstack((X[ref,],np.delete(X,ref)))      

    if fix != False:
        X  = np.hstack((np.array(fix),X))
        vv = np.vstack((np.zeros((len(fix),vv.shape[1])),vv))
    
    vv  = np.sign(np.real(vv))*np.abs(vv)     
    idx = np.argsort(X)         
    it  = np.argsort(fn)
    
    plt.figure(figsize=(2*len(fn),5))
    
    for i, k in enumerate(it):
        plt.subplot(1,fn.shape[0],i+1)
        plt.plot(0.97*vv[idx,k]/np.max(np.abs(vv[:,k])),X[idx])
        plt.xlim((-1,1))                    
        plt.ylim((0,X.max()))
        plt.xticks(**t_for)
        plt.yticks([])
        plt.xlabel(r'$f_n$ = {:.3f} Hz''\n'r'$\zeta$ = {:.2f} %'
             .format(fn[k],zt[k]*100),**l_for)            
        if i == 0:
            plt.yticks(np.linspace(0,X.max(),10),**t_for)
      
    plt.suptitle(title + ' Mode Shapes',**a_for)
    plt.tight_layout(rect=[0, -0.02, 1, 0.97]) 
    
    plt.show()
    return

#-----------------------------------------------------------------------------
        
def plot_3das1d(fn, zt, q, X, title, ref=False):
    """
    Plot three-dimensional mode shapes 
    
    Parameters
    -------          
    fn : ndarray
        Eigenfrequencies array.
    zt : ndarray
        Damping ratios array.       
    q : ndarray
        Array that contains the mode shapes as columns.
    X : ndarray
        Height of the l sensors.
    title : string
        Graph title.
    ref : tuple, list, optional
        List of reference sensors.  
    """ 

    a_for = {'fontname':'Times New Roman','size':14} 
    g_for = {'family'  :'Times New Roman','size':12}
    l_for = {'fontname':'Times New Roman','size':12}        
    t_for = {'fontname':'Times New Roman','size':10}

    if ref != False: 
        X  = np.hstack((X[ref],np.delete(X,ref)))
    
    q   = np.sign(np.real(q))*np.abs(q)  
    it  = np.argsort(fn)
    X   = np.hstack((0,X)) 
    q   = np.vstack((np.zeros((3,len(fn))),q))
    idx = np.argsort(X)
    
    plt.figure(figsize=(2*len(fn),5))

    for ii, kk in np.ndenumerate(it):
        
        q[:,kk] = q[:,kk]/np.max(np.abs(q[:,kk])) 
        
        plt.subplot(1,fn.shape[0],ii[0]+1)
        plt.plot(q[0::3,kk][idx],X[idx],'k',  linewidth=3)
        plt.plot(q[1::3,kk][idx],X[idx],'r--',linewidth=2)
        plt.plot(q[2::3,kk][idx],X[idx],'g:', linewidth=4)
        plt.xticks(**t_for)
        plt.yticks([])
        plt.xlim((-1,1))
        plt.ylim((0,X.max()))
        plt.xlabel(r'$f_n$ = {:.3f} Hz''\n'r'$\zeta$ = {:.2f} %'
             .format(fn[kk],zt[kk]*100),**l_for)
        if ii[0] == 0:
            plt.yticks(np.linspace(0,X.max(),10),**t_for)
            plt.legend(('x', 'y',r'$\theta_z$'), loc='lower left',
                       prop=g_for, handlelength=1.2, handletextpad=0.4)
        
    plt.suptitle(title +' Mode Shapes',**a_for)
    plt.tight_layout(rect=[0, 0.03, 1, 0.97])    
    plt.show()        
    
    return