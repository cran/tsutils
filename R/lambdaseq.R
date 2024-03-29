#' Generate sequence of lambda for LASSO regression
#'
#' Calculates the \code{lambdaMax} value, which is the penalty term (lambda) beyond which coefficients are guaranteed to be all zero and provides a sequence of \code{nLambda} values to \code{lambdaMin} in logarithmic descent.
#'
#' @param x matrix of regressors. See \code{glmnet}.
#' @param y response variable. See \code{glmnet}.
#' @param weight vector of \code{length(nrow(y))} for weighted LASSO estimation. See \code{glmnet}.
#' @param alpha elastic net mixing value. See \code{glmnet}.
#' @param standardise if \code{TRUE}, then variables are standardised.
#' @param lambdaRatio ratio between \code{lambdaMax} and \code{lambdaMin}. That is, \code{lambdaMin <- lambdaMax * lambdaRatio}.
#' @param nLambda length of the lambda sequence.
#' @param addZeroLambda if \code{TRUE}, then set the last value in the lambda sequence to 0, which is the OLS solution.
#'
#' @return A list that contains:
#' \itemize{
#' \item \code{lambda}: sequence of lambda values, from \code{lambdaMax} to \code{lambdaMin}.
#' \item \code{lambdaMin}: minimal lambda value.
#' \item \code{lambdaMax}: maximal lambda value.
#' \item \code{nullMSE}: MSE of the fit using just a constant term.
#' }
#'
#' @author Oliver Schaer, \email{info@oliverschaer.ch},
#' @author Nikolaos Kourentzes, \email{nikolaos@kourentzes.com}.
#'
#' @references
#' Hastie, T., Tibshirani, R., & Wainwright, M. (2015). Statistical learning with sparsity: the lasso and generalizations. CRC press.
#'
#' @keywords ts Regression
#'
#' @examples
#' y <- mtcars[,1]
#' x <- as.matrix(mtcars[,2:11])
#' lambda <- lambdaseq(x, y)$lambda
#'
#' \dontrun{
#'   library(glmnet)
#'   fit.lasso <- cv.glmnet(x, y, lambda = lambda)
#'   coef.lasso <- coef(fit.lasso, s = "lambda.1se")
#' }
#'
#' @export lambdaseq

lambdaseq <- function(x, y, weight = NA, alpha = 1, standardise = TRUE,
                      lambdaRatio = 0.0001, nLambda = 100, addZeroLambda = FALSE){

  lambdaFit <- computeLambdaMax(x, y, weight, alpha, standardise)
  lambdaMax <- lambdaFit$lambdaMax
  lambdaMin <- lambdaMax * lambdaRatio

  loghi <- log(lambdaMax)
  loglo <- log(lambdaMin)
  logrange <- loghi - loglo
  interval <- -logrange/(nLambda-1)

  lambda <-  exp(seq.int(from = loghi, to = loglo, by = interval))
  if(addZeroLambda == T){
    lambda[length(lambda)] <-  0
  }else{
    lambda[length(lambda)] <-  lambdaMin;
  }

  return(list("lambda" = lambda, "lambdaMin" = lambdaMin,
              "lambdaMax" = lambdaMax, "nullMSE" = lambdaFit$nullMSE))
}

computeLambdaMax <- function(x, y, weight = NA, alpha = 1, standardise = T){

  # Calculates the lambdaMax value, which is the penalty term (lambda) beyond
  # which coefficients are guaranteed to be all zero using 0*OLS solution
  #
  # nullMse is the mse of the fit using just a constant term. It is provided
  # in this function as a convenience, because it needs to be calculated in
  # the same context as lambdaMax whenever lambdaMax is calculated.
  #
  # Input values description
  # x                       expects matrix
  # z                       y values as vector
  # weight [default = NA]   Vector of length(nrow(y)) for weighted LASSO estimation
  # alpha [default = 1, range(0,1)]
  #                         Elastic net mixing value, or the relative balance
  #                         between L2 and L1 penalty (default 1, range (0,1]).
  #                         Alpha = 1 --> lasso, otherwise elastic net.
  #                         Alpha near zero --> nearly ridge regression.
  # standardise [default=T] Standardises variables
  # Nikolaos Kourentzes, 2017 <nikolaos@kourentzes.com>
  # Oliver Schaer, 2017 <info@oliverschaer.ch>

  if(!anyNA(weight)){

    observationWeight <- T
    weight <-  t(weight)

    # Normalized weights are used for standardization and calculating lambdaMax
    normalizedweight <-  as.vector(weight/sum(weight))

  }else{
    observationWeight <- F
  }

  N <- nrow(x)

  # If we were asked to standardise the predictors, do so here because
  # the calculation of lambdaMax needs the predictors as we will use them to perform fits.

  if(standardise == T){
    # If X has any constant columns, we want to protect against
    # divide-by-zero in normalizing variances.

    constantPredictors <- rep(0, ncol(x))
    constantPredictors[which(apply(x, 2, function(x) sum(length(unique(x)))) == 1)] <- 1

    if(observationWeight == F){
      # Center and scale
      x0 <-  scale(x, center = T, scale = T)
      x0[is.nan(x0)] <- 0

    }else{

      # Weighted center and scale
      muX <-  as.vector(normalizedweight %*% x)
      muX.m <- tcrossprod(rep(1, length(muX)), muX)
      x0 <- x - muX.m[1:N,]

      sigmaX = sqrt(normalizedweight %*% (x0^2))

      # Avoid divide by zero with constant predictors
      sigmaX[which(constantPredictors == 1)] <-  1
      x0 <- x0 / sigmaX[col(x0)]
    }
  }else{

    if(observationWeight == F){
      # Center
      muX = colMeans(x)
      muX.m <- tcrossprod(rep(1, length(muX)), muX)
      x0 <- x - muX.m[1:N,]
    }else{
      # Weighted center
      muX = as.vector(normalizedweight %*% x)
      muX.m <- tcrossprod(rep(1, length(muX)), muX)
      x0 <- x - muX.m[1:N,]
    }
  }

  # If using observation weights, make a weighted copy of the
  # predictor matrix, for use in weighted dot products.

  if(observationWeight == T){
    wX0 = x0 * as.vector(weight)
  }

  if(observationWeight == F){
    muY = mean(y)
  }else{
    muY = weight %*% y
  }

  # Y0 = bsxfun(@minus,Y,muY);
  y0 = y - muY

  #Calculate max lambda that permits non-zero coefficients

  if(observationWeight == F){
    dotp = abs(t(x0) %*% y0)
    lambdaMax = max(dotp)/(N*alpha)
  }else{
    dotp = abs(colSums(wX0 * y0))
    lambdaMax = max(dotp)/alpha
  }

  if(observationWeight == F){
    nullMSE = mean(y0^2)
  }else{
    # This works because weights are normalized and y0 is already weight-centered.
    nullMSE = weight %*% (y0^2)
  }

  return(list("nullMSE" = nullMSE, "lambdaMax" = lambdaMax))
}
