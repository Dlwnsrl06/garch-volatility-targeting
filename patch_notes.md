08-12-2026:  
  - garch_model.py
    - Fixed a crash-causing bug: Original code hid all Python warnings with warnings.filterwarnings("ignore"), not just the GARCH-specific ones. That's risky because it can silently swallow real bugs elsewhere. Removed it; the one warning that mattered (optimizer didn't converge) is already handled by show_warning=False.
    - Fixed silent failure risk: The model never checked whether each daily GARCH fit actually succeeded. Added a check on res.convergence_flag. If a fit fails to converge, it's now logged instead of quietly accepted as if it were fine.
    - Added a speed option: Original code re-trained the full GARCH model from scratch every single day (2,160 times), which is correct but slow. Added a refit_every setting: e.g. refit_every=5 re-trains once a week and reuses those parameters for the days in between, still with zero lookahead. Default is 1 (daily), so nothing changes unless you turn it up.
    - Trimmed wasted computation: The forecast call was computing predictions for every date in the training window and throwing away all but the last one. Now it only computes the one forecast actually used.
    - Added visibility:
      - Progress printout every 250 days, so a long-running loop doesn't look frozen.
      - New refit_day column in the output, marking which rows came from a fresh fit vs. a reused one.
