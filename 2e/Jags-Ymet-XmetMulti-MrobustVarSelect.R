# Jags-Ymet-XmetMulti-MrobustVarSelect.R 
# Accompanies the book:
#  Kruschke, J. K. (2015). Doing Bayesian Data Analysis, Second Edition: 
#  A Tutorial with R, JAGS, and Stan. Academic Press / Elsevier.

source("DBDA2E-utilities.R")

#===============================================================================

genMCMC = function( data , xName="x" , yName="y" , 
                    numSavedSteps=10000 , thinSteps=1 , saveName=NULL ,
                    runjagsMethod=runjagsMethodDefault , 
                    nChains=nChainsDefault ) { 

  #-----------------------------------------------------------------------------
  # THE DATA.
  y = data[,yName]
  x = as.matrix(data[,xName],ncol=length(xName))
  # Do some checking that data make sense:
  if ( any( !is.finite(y) ) ) { stop("All y values must be finite.") }
  if ( any( !is.finite(x) ) ) { stop("All x values must be finite.") }
  cat("\nCORRELATION MATRIX OF PREDICTORS:\n ")
  show( round(cor(x),3) )
  cat("\n")
  flush.console()
  # Specify the data in a list, for later shipment to JAGS:
  dataList = list(
    x = x ,
    y = y ,
    Nx = dim(x)[2] ,
    Ntotal = dim(x)[1]
  )
  #-----------------------------------------------------------------------------
  # THE MODEL.
  modelString = "
  # Standardize the data:
  data {
    ym <- mean(y)
    ysd <- sd(y)
    for ( i in 1:Ntotal ) {
      zy[i] <- ( y[i] - ym ) / ysd
    }
    for ( j in 1:Nx ) {
      xm[j]  <- mean(x[,j])
      xsd[j] <-   sd(x[,j])
      for ( i in 1:Ntotal ) {
        zx[i,j] <- ( x[i,j] - xm[j] ) / xsd[j]
      }
    }
  }
  # Specify the model for standardized data:
  model {
    for ( i in 1:Ntotal ) {
      zy[i] ~ dt( zbeta0 + sum( delta[1:Nx] * zbeta[1:Nx] * zx[i,1:Nx] ) , 
                  1/zsigma^2 , nu )
    }
    # Priors vague on standardized scale:
    zbeta0 ~ dnorm( 0 , 1/2^2 )  # 
    for ( j in 1:Nx ) {
      zbeta[j] ~ dt( 0 , 1/sigmaBeta^2 , 1 ) 
      delta[j] ~ dbern( 0.5 )
      #delta[j] ~ dbern( theta ) # estimate prior inclusion probability
    }
    # theta ~ dbeta(1,1) # estimate prior inclusion probability
    zsigma ~ dunif( 1.0E-5 , 1.0E+1 )
    ## Uncomment one of the following specifications for sigmaBeta:
    # sigmaBeta <- 2.0
    # sigmaBeta ~ dunif( 1.0E-5 , 1.0E+2 )
    sigmaBeta ~ dgamma(1.1051,0.1051) # mode 1.0, sd 10.0
    # sigmaBeta <- 1/sqrt(tauBeta) ; tauBeta ~ dgamma(0.001,0.001) 
    nu ~ dexp(1/30.0)
    # Transform to original scale:
    beta[1:Nx] <- ( delta[1:Nx] * zbeta[1:Nx] / xsd[1:Nx] )*ysd
    beta0 <- zbeta0*ysd  + ym - sum( delta[1:Nx] * zbeta[1:Nx] * xm[1:Nx] 
                                     / xsd[1:Nx] )*ysd
    sigma <- zsigma*ysd
  }
  " # close quote for modelString
  # Write out modelString to a text file
  writeLines( modelString , con="TEMPmodel.txt" )
  #-----------------------------------------------------------------------------
  # INTIALIZE THE CHAINS.
  # Let JAGS do it...
    
  #-----------------------------------------------------------------------------
  # RUN THE CHAINS
  parameters = c( "beta0" ,  "beta" ,  "sigma", "delta" , "sigmaBeta" ,
                  "zbeta0" , "zbeta" , "zsigma", "nu"  
                  # , theta # estimate prior inclusion probability
                  )
  adaptSteps = 500  # Number of steps to "tune" the samplers
  burnInSteps = 1000
  runJagsOut <- run.jags( method=runjagsMethod ,
                          model="TEMPmodel.txt" , 
                          monitor=parameters , 
                          data=dataList ,  
                          #inits=initsList , 
                          n.chains=nChains ,
                          adapt=adaptSteps ,
                          burnin=burnInSteps , 
                          sample=ceiling(numSavedSteps/nChains) ,
                          thin=thinSteps ,
                          summarise=FALSE ,
                          plots=FALSE )
  codaSamples = as.mcmc.list( runJagsOut )
  # resulting codaSamples object has these indices: 
  #   codaSamples[[ chainIdx ]][ stepIdx , paramIdx ]
  if ( !is.null(saveName) ) {
    save( codaSamples , file=paste(saveName,"Mcmc.Rdata",sep="") )
  }
  return( codaSamples )
} # end function

#===============================================================================

smryMCMC = function(  codaSamples , 
                      saveName=NULL ) {
  summaryInfo = NULL
  mcmcMat = as.matrix(codaSamples,chains=TRUE)
  paramName = colnames(mcmcMat)
  for ( pName in paramName ) {
    summaryInfo = rbind( summaryInfo , summarizePost( mcmcMat[,pName] ) )
  }
  rownames(summaryInfo) = paramName
  summaryInfo = rbind( summaryInfo , 
                       "log10(nu)" = summarizePost( log10(mcmcMat[,"nu"]) ) )
  if ( !is.null(saveName) ) {
    write.csv( summaryInfo , file=paste(saveName,"SummaryInfo.csv",sep="") )
  }
  return( summaryInfo )
}

#===============================================================================

plotMCMC = function( codaSamples , data , xName="x" , yName="y" ,
                     showCurve=FALSE ,  pairsPlot=FALSE ,
                     saveName=NULL , saveType="jpg" ) {
  # showCurve is TRUE or FALSE and indicates whether the posterior should
  #   be displayed as a histogram (by default) or by an approximate curve.
  # pairsPlot is TRUE or FALSE and indicates whether scatterplots of pairs
  #   of parameters should be displayed.
  #-----------------------------------------------------------------------------
  y = data[,yName]
  x = as.matrix(data[,xName])
  mcmcMat = as.matrix(codaSamples,chains=TRUE)
  chainLength = NROW( mcmcMat )
  zbeta0 = mcmcMat[,"zbeta0"]
  zbeta  = mcmcMat[,grep("^zbeta\\[",colnames(mcmcMat))]
  zsigma = mcmcMat[,"zsigma"]
  beta0 = mcmcMat[,"beta0"]
  beta  = mcmcMat[,grep("^beta\\[",colnames(mcmcMat))]
  delta  = mcmcMat[,grep("^delta\\[",colnames(mcmcMat))]
  sigma = mcmcMat[,"sigma"]
  nu = mcmcMat[,"nu"]
  log10nu = log10(nu)
  #-----------------------------------------------------------------------------
  # Compute R^2 for credible parameters:
  YcorX = cor( y , x ) # correlation of y with each x predictor
  Rsq = (delta * zbeta) %*% matrix( YcorX , ncol=1 )
  #-----------------------------------------------------------------------------
  # Show results for each subset of predictors:
  # This is inelegant code, intended only for a basic illustration.
  # Recall that delta[j] is inclusion coefficient for predictor j.
  parameterNames = colnames(mcmcMat)
  deltaCol = grep("delta\\[",parameterNames)
  Npred = length(deltaCol)
  # Show overall inclusion probabilities of each predictor:
  cat("Inclusion probability of each predictor:\n")
  show( xName )
  show( colMeans(mcmcMat[,deltaCol]) )
  # Function to make binary vector of non-neg integer:
  binVecOfI = function( i ) { 
    if ( i ) { c( i %% 2 , binVecOfI( i %/% 2 ) ) } else { NULL }
  }
  # Awkward construction of all possible subsets of predictors:
  for ( modelIdx in 1:(2^Npred) ) {
    includePred = rep(0,Npred)  
    binVec = binVecOfI(modelIdx-1)
    if ( length(binVec) ) {
      for(j in 1:length(binVec) ) { includePred[j]=binVec[j] }
    }
    # Extract rows of mcmcMat with this combination of included predictors:
    cat("  Checking model ",modelIdx," of ",2^Npred," (",includePred,") ...\n")
    includeSteps = apply( mcmcMat[,deltaCol] , 1 , 
                          function(m){ (all(m==includePred)) } )
    if ( sum(includeSteps)>50 ) { # make graph if enough steps
      includeMat = mcmcMat[includeSteps,]
      modelProb = nrow(includeMat)/nrow(mcmcMat)
      Ncol = min(Npred+2,6)
      Nrow = 1+(Npred)%/%Ncol
      openGraph(width=Ncol*2.25,height=Nrow*2.0)
      layout( matrix( 1:(Ncol*Nrow) , ncol=Ncol , nrow=Nrow , byrow=TRUE ) )
      xLim = range(mcmcMat[,"beta0"])
      plotPost( includeMat[,"beta0"] , xlab="Intercept" , xlim=xLim , 
                cenTend="median" , cex.main=2 , border="skyblue" ,
                main=bquote("Model Prob"==.(round(modelProb,3))))
      for ( j in 1:Npred ) {
        parName = paste0("beta[",j,"]")
        if ( includePred[j] ) {
          xLim = range(mcmcMat[,parName])
          plotPost( includeMat[,parName] , cenTend="median" , border="skyblue" , 
                    xlab=parName , xlim=xLim , main=xName[j] )
        } else { 
          plot( x=-99,y=-99,xlab="",ylab="",xlim=c(-1,1),ylim=c(-1,1),
                bty="n",axes=FALSE)
          text( 0,0,adj=c(0.5,0.5),labels=bquote(delta[.(j)]==0), cex=1.5)
        }
      }
      plotPost( Rsq[includeSteps] , xlab=bquote(R^2) , 
                main="Prop Var Accntd" , 
                cenTend="median" , border="skyblue" )
      saveGraph( file=paste0(saveName,paste0(includePred,collapse="")) , 
                 type=saveType )
    }
  }
  #-----------------------------------------------------------------------------
  if ( pairsPlot ) {
    # Plot the parameters pairwise, to see correlations:
    openGraph()
    nPtToPlot = 1000
    plotIdx = floor(seq(1,chainLength,by=chainLength/nPtToPlot))
    panel.cor = function(x, y, digits=2, prefix="", cex.cor, ...) {
      usr = par("usr"); on.exit(par(usr))
      par(usr = c(0, 1, 0, 1))
      r = (cor(x, y))
      txt = format(c(r, 0.123456789), digits=digits)[1]
      txt = paste(prefix, txt, sep="")
      if(missing(cex.cor)) cex.cor <- 0.8/strwidth(txt)
      text(0.5, 0.5, txt, cex=1.25 ) # was cex=cex.cor*r
    }
    pairs( cbind( beta0 , beta , sigma , log10nu )[plotIdx,] ,
           labels=c( "beta[0]" , 
                     paste0("beta[",1:ncol(beta),"]\n",xName) , 
                     expression(sigma) ,  expression(log10(nu)) ) , 
           lower.panel=panel.cor , col="skyblue" )
    if ( !is.null(saveName) ) {
      saveGraph( file=paste(saveName,"PostPairs",sep=""), type=saveType)
    }
  }
  #-----------------------------------------------------------------------------
  # Marginal histograms:
  
  decideOpenGraph = function( panelCount , saveName , finished=FALSE , 
                              nRow=2 , nCol=3 ) {
    # If finishing a set:
    if ( finished==TRUE ) {
      if ( !is.null(saveName) ) {
        saveGraph( file=paste0(saveName,ceiling((panelCount-1)/(nRow*nCol))), 
                   type=saveType)
      }
      panelCount = 1 # re-set panelCount
      return(panelCount)
    } else {
    # If this is first panel of a graph:
    if ( ( panelCount %% (nRow*nCol) ) == 1 ) {
      # If previous graph was open, save previous one:
      if ( panelCount>1 & !is.null(saveName) ) {
        saveGraph( file=paste0(saveName,(panelCount%/%(nRow*nCol))), 
                   type=saveType)
      }
      # Open new graph
      openGraph(width=nCol*7.0/3,height=nRow*2.0)
      layout( matrix( 1:(nRow*nCol) , nrow=nRow, byrow=TRUE ) )
      par( mar=c(4,4,2.5,0.5) , mgp=c(2.5,0.7,0) )
    }
    # Increment and return panel count:
    panelCount = panelCount+1
    return(panelCount)
    }
  }
  
  # Original scale:
  panelCount = 1
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMarg") )
  histInfo = plotPost( beta0 , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(beta[0]) , main="Intercept" )
  for ( bIdx in 1:ncol(beta) ) {
    panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMarg") )
    histInfo = plotPost( beta[,bIdx] , cex.lab = 1.75 , showCurve=showCurve ,
                         xlab=bquote(beta[.(bIdx)]) , main=xName[bIdx] )
  }
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMarg") )
  histInfo = plotPost( sigma , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(sigma) , main=paste("Scale") )
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMarg") )
  histInfo = plotPost( log10nu , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(log10(nu)) , main=paste("Normality") )
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMarg") )
  histInfo = plotPost( Rsq , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(R^2) , main=paste("Prop Var Accntd") )
  panelCount = decideOpenGraph( panelCount , finished=TRUE , saveName=paste0(saveName,"PostMarg") )
  
  # Standardized scale:
  panelCount = 1
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMargZ") )
  histInfo = plotPost( zbeta0 , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(z*beta[0]) , main="Intercept" )
  for ( bIdx in 1:ncol(beta) ) {
    panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMargZ") )
    histInfo = plotPost( zbeta[,bIdx] , cex.lab = 1.75 , showCurve=showCurve ,
                         xlab=bquote(z*beta[.(bIdx)]) , main=xName[bIdx] )
  }
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMargZ") )
  histInfo = plotPost( zsigma , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(z*sigma) , main=paste("Scale") )
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMargZ") )
  histInfo = plotPost( log10nu , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(log10(nu)) , main=paste("Normality") )
  panelCount = decideOpenGraph( panelCount , saveName=paste0(saveName,"PostMargZ") )
  histInfo = plotPost( Rsq , cex.lab = 1.75 , showCurve=showCurve ,
                       xlab=bquote(R^2) , main=paste("Prop Var Accntd") )
  panelCount = decideOpenGraph( panelCount , finished=TRUE , saveName=paste0(saveName,"PostMargZ") )
  
  #-----------------------------------------------------------------------------
}
#===============================================================================
