# ---------------------------------------------------------------------------
# Program Name:         H2A_update-higher_eff.R
# Author:               Patrick O'Rourke, 
# Date Last Updated:    7/8/21
# Program Purpose:      Update GCAM H2 production assumptions with latest NREL
#                       H2A data (2018).
# Input Files:
#     1.) H2A non-energy cost data:        H2A_prod_data.xlsx, sheet = "NE_cost"
#     2.) H2A coeff & efficiency data:     H2A_prod_data.xlsx, sheet = "coef" 
#     3.) GCAM power sector capital costs: L223.GlobalTechCapital_elec.csv
#     4.) GCAM power sector efficiencies:  L223.GlobalTechEff_elec.csv
#
# Output Files:
#     1.) GCAM H2 production non-energy costs:  A25.globaltech_cost.csv
#     2.) GCAM H2 production efficiencies:      A25.globaltech_eff.csv
#
# Notes: 1) NREL H2A v2018 did not include the following H2 production technologies:
#           bio + CCS, coal w/o CCS, coal + CCS (future), nuclear H2 prod,
#           solar electrolysis, and wind electrolysis.
#
#           A) Base year bio + CCS and coal w/o CCS assumptions were created by leveraging the ratio between
#              comparable IGCC technologies in the power sector. 
#   
#              Coal w/o CCS was given the same improvement rate as the NREL H2A biomass w/o CCS technology.
#
#              The "difference" (cost adder or efficiency loss) between "CCS" and "no CCS" technology pairs for
#              coal and biomass was then reduced overtime by leveraging the reduction in this difference for 
#              the comparable IGCC technologies in the power sector. 
# 
#              Coal w/CCS and biomass w/CCS were then extended by adding this "difference" (cost adder or efficiency 
#              loss) to the non-CCS version of the H2 production technology, for each period.
#                          
#           B) Wind and solar electrolysis were created by adding the cost of panels and turbines to the H2A electrolysis plant
#              using NREL ATB 2019 data.
#
#           C) Nuclear thermal splitting utilized an earlier version of H2A data (2008). This data was updated by modyfing
#              H2A reactor costs to be consistent with NREL ATB's 2019 data. Max improvement leverages nuclear reactor
#              improvement from GCAM power sector for Gen_III reactors
#
# TODO: Consider various inputs for efficiency assumptions
# ------------------------------------------------------------------------------
# 0.5 Pick options and set WD

#   A.) Pick options
        
#       1.) Multiple inputs considered? Impacts efficiencies only. 
#           ( TRUE = multiple inputs have efficiencies, 
#             FALSE = convert all to the H2A "feedstock" and sum for 1 efficiency)
            multiple_inputs <- FALSE

#   B.) Set WD
      setwd( "/Users/patrickorourke/Desktop/GCAM-H2A_update-processing/input" )

# ------------------------------------------------------------------------------
      
# I. Load packages and data
      
#   A.) Load packages
        library( "dplyr" )
        library( "tidyr" )
        library( "openxlsx" ) # Doesn't work on PC without Rtool (works on MAC)
      
#   B.) Load data
      
#     1.) H2A data
      H2A_NE_cost <- read.xlsx( xlsxFile = "H2A_prod_data.xlsx",
                                sheet = "NE_cost", startRow = 4 )
      
      H2A_coef <- read.xlsx( xlsxFile = "H2A_prod_data.xlsx",
                             sheet = "coef", startRow = 4 ) 
      
#     2.) GCAM data for power sector
      GCAM_elec_cap_cost <- read.csv( "L223.GlobalTechCapital_elec.csv", skip = 2,
                                      header = TRUE )
      
      GCAM_elec_eff <- read.csv( "L223.GlobalTechEff_elec.csv", skip = 1,
                                 header = TRUE )
      
#     3.) GCAM data for gas processing
      GCAM_en_transf_coef <- read.csv( "A22.globaltech_coef.csv", skip = 5,
                                 header = TRUE )
      
# ------------------------------------------------------------------------------
# II. Set script constants

# A. Conversions for energy
        
#   1.) GJ/mmBTU
        GJ_per_mmBTU <- 1.055
         
#   2.) MMBTU/KgH2 - LHV
        mmBTU_per_kgH2 <- 0.113939965425114 # Source: H2 CCTP Workbook.xls (Used for older GCAM assumptions)
         
#   3.) GJ/kgH2 - LHV 
        GJ_per_kgH2 <- GJ_per_mmBTU * mmBTU_per_kgH2 # = 0.1202067
        
#   4.) GJ fossil / GJ elec
        GJ_fuel_per_GJ_elec <- 3
         
#   5.) GJ bio / GJ bio gas
        GJ_bio_per_GJ_bio_gas <- GCAM_en_transf_coef %>% 
          dplyr::filter( technology == "biomass gasification" ) %>% 
          dplyr::select( X2020 )
    
        GJ_bio_per_GJ_bio_gas <- GJ_bio_per_GJ_bio_gas[[1]] # = 1.343 
        
# B. Conversions for USD dollars
        
#   1.) 2016 to 1975 (Base year for conversion is 2012 [2012 = 100])
        conv_2016_to_2012 <- 100 / 105.722 # Source: https://fred.stlouisfed.org/series/A191RD3A086NBEA
        conv_2012_to_1975 <- 29.849 / 100  # Source: https://fred.stlouisfed.org/series/A191RD3A086NBEA
        conv_2016_to_1975 <- conv_2016_to_2012 * conv_2012_to_1975
              
#   2.) 2005 to 1975 (Base year for conversion is 2012 [2012 = 100])
        conv_2005_to_2012 <- 100/87.421 # Source: https://fred.stlouisfed.org/series/A191RD3A086NBEA
        conv_2005_to_1975 <- conv_2005_to_2012 * conv_2012_to_1975
        
# C. Years (with and without Xs)
     H2A_years <- c( "2015", "2040" )
     H2A_Xyears <- paste0( "X", H2A_years )
        
     GCAM_H2_input_years <- paste( c( 1971, seq( 2015, 2100, 5 ) ) )
     GCAM_H2_input_Xyears <- paste0( "X", GCAM_H2_input_years )
         
     H2A_missing_Xyears <- subset( GCAM_H2_input_Xyears, !( GCAM_H2_input_Xyears %in% H2A_Xyears )  )
    
# ------------------------------------------------------------------------------
# III. Define script functions

#   A. Convert NE cost (from per kg of H2, to per GJ of H2)
    convert_NE_cost <- function( col ){ col / GJ_per_kgH2 }

#   B. Remove "Xs" from year columns
    remove_X_years <- function(col){ gsub( "X", "", col ) }
      
# ------------------------------------------------------------------------------
# IV. Process electricity sector data used for creation of technologies
#     missing from H2A

# A. Calculate ratio of overnight capital costs for IGCC technology w/ and w/o CCS
#     Costs: (coal technology only)
      elec_IGCC_2015_cost_ratio <- GCAM_elec_cap_cost %>% 
          dplyr::filter( technology %in% c( "coal (IGCC)", "coal (IGCC CCS)" ), 
                     year == 2015 ) %>% 
          tidyr::spread( technology, capital.overnight ) %>% 
          dplyr::rename( coal_IGCC = "coal (IGCC)",
                         coal_IGCC_CCS = "coal (IGCC CCS)" ) %>% 
          dplyr::mutate( IGCC_CCS_no_CCS_2015_ratio = coal_IGCC_CCS / coal_IGCC ) %>% 
          dplyr::select( sector.name, subsector.name, IGCC_CCS_no_CCS_2015_ratio )
    
#     Efficiency:
      elec_IGCC_2015_eff_ratio <- GCAM_elec_eff %>% 
          dplyr::filter( technology %in% c( "coal (IGCC)", "coal (IGCC CCS)",
                                            "biomass (IGCC)", "biomass (IGCC CCS)" ), 
                         year == 2015 ) %>% 
          dplyr::mutate( technology = dplyr::if_else( technology %in% c( "coal (IGCC CCS)", "biomass (IGCC CCS)" ),
                                                      "IGCC_CCS",
                                      dplyr::if_else( technology %in% c( "coal (IGCC)", "biomass (IGCC)" ),
                                                     "IGCC_no_CCS", NA_character_ ) ) ) %>% 
          tidyr::spread( technology, efficiency ) %>% 
          dplyr::mutate( IGCC_CCS_no_CCS_2015_ratio = IGCC_CCS / IGCC_no_CCS ) %>% 
          dplyr::select( sector.name, subsector.name, IGCC_CCS_no_CCS_2015_ratio )
    
      elec_IGCC_2015_eff_ratio_bio <- elec_IGCC_2015_eff_ratio %>% 
        dplyr::filter( subsector.name == "biomass" )
      
      elec_IGCC_2015_eff_ratio_coal <- elec_IGCC_2015_eff_ratio %>% 
        dplyr::filter( subsector.name == "coal" )
      
      
# B. Calculate improvement rate of CCS for biomass and coal IGCC electricity technologies
#    Costs:
     elec_IGCC_CCS_cost_improvement <- GCAM_elec_cap_cost %>% 
         dplyr::filter( technology %in% c( "coal (IGCC)", "coal (IGCC CCS)",
                                           "biomass (IGCC)", "biomass (IGCC CCS)" ),
                        year %in% c( 2015, 2100 ) ) %>% 
         dplyr::mutate( technology = dplyr::if_else(  technology %in% c( "coal (IGCC)", "biomass (IGCC)" ),
                                                      "without_CCS", 
                                    dplyr::if_else(  technology %in% c( "coal (IGCC CCS)", "biomass (IGCC CCS)" ),
                                                     "with_CCS", NA_character_ ) ) ) %>% 
         tidyr::spread( technology, capital.overnight ) %>% 
         dplyr::mutate( CCS_add_cost = with_CCS - without_CCS ) %>% 
         dplyr::select( sector.name, subsector.name, year, CCS_add_cost ) %>% 
         tidyr::spread( year, CCS_add_cost ) %>% 
         dplyr::mutate( max_improvement = ( 1 - ( !!rlang::sym( "2100" ) / !!rlang::sym( "2015" )  ) ),
                        technology = dplyr::if_else( subsector.name == "coal", "coal (IGCC CCS)",
                                     dplyr::if_else( subsector.name == "biomass", "biomass (IGCC CCS)", 
                                                     NA_character_ ) ) ) %>% 
         dplyr::select( sector.name, subsector.name, technology, max_improvement )
    
#     Efficiency:
      elec_IGCC_CCS_eff_improvement <- GCAM_elec_eff %>% 
         dplyr::filter( technology %in% c( "coal (IGCC)", "coal (IGCC CCS)",
                                           "biomass (IGCC)", "biomass (IGCC CCS)" ),
                        year %in% c( 2015, 2100 ) ) %>% 
         dplyr::mutate( technology = dplyr::if_else(  technology %in% c( "coal (IGCC)", "biomass (IGCC)" ),
                                                      "without_CCS", 
                                     dplyr::if_else(  technology %in% c( "coal (IGCC CCS)", "biomass (IGCC CCS)" ),
                                                      "with_CCS", NA_character_ ) ) ) %>% 
         tidyr::spread( technology, efficiency ) %>% 
         dplyr::mutate( CCS_sub_eff = with_CCS - without_CCS ) %>% 
         dplyr::select( sector.name, subsector.name, year, CCS_sub_eff ) %>% 
         tidyr::spread( year, CCS_sub_eff ) %>% 
         dplyr::mutate( max_improvement = ( 1 - ( !!rlang::sym( "2100" ) / !!rlang::sym( "2015" )  ) ),
                        technology = dplyr::if_else( subsector.name == "coal", "coal (IGCC CCS)",
                                                     dplyr::if_else( subsector.name == "biomass", "biomass (IGCC CCS)", 
                                                                     NA_character_ ) ) ) %>% 
         dplyr::select( sector.name, subsector.name, technology, max_improvement )
     
# C. Costs: Calculate max improvement rate of nuclear power generation capital overnight costs
     elec_nuclear_cost_improvement <- GCAM_elec_cap_cost %>% 
       dplyr::filter( technology == "Gen_III" ,
                      year %in% c( 2015, 2100 ) ) %>% 
       tidyr::spread( year, capital.overnight ) %>% 
       dplyr::mutate( max_improvement = ( 1 - ( !!rlang::sym( "2100" ) / !!rlang::sym( "2015" )  ) ) ) %>% 
       dplyr::select( sector.name, subsector.name, technology, max_improvement )
     
# ------------------------------------------------------------------------------
# V. Process cost data for each H2A technology

# A. Convert Units
  H2A_NE_cost_conv_units <- H2A_NE_cost %>% 
          dplyr::select( -notes ) %>% 
          dplyr::rename( "X2015" = "2015",
                         "X2040" = "2040" ) %>% 
          dplyr::mutate_at( .vars = H2A_Xyears,
                            .funs = convert_NE_cost ) %>% 
          dplyr::mutate( X2015 = dplyr::if_else(  units == "$2016/kg H2", 
                                                  X2015 * conv_2016_to_1975,
                                 dplyr::if_else(  units == "$2005/kg H2",
                                                  X2015* conv_2005_to_1975,
                                                  NA_real_ ) ) ) %>% 
          dplyr::mutate( X2040 = dplyr::if_else(  units == "$2016/kg H2", 
                                                  X2040 * conv_2016_to_1975,
                                 dplyr::if_else(  units == "$2005/kg H2",
                                                  X2040* conv_2005_to_1975,
                                                  NA_real_ ) ) ) %>% 
          dplyr::mutate( units = "$1975/GJ H2" )

# B. Add X2015 value for coal w/o CCS and bio w/CCS
     existing_coal_bio <- H2A_NE_cost_conv_units %>% 
       dplyr::filter( technology %in% c( "biomass to H2", "coal chemical CCS" ) )
     
     bio_no_CCS <- existing_coal_bio %>% 
       dplyr::filter( technology == "biomass to H2" ) 
     
     bio_no_CCS_impro_2040 <- bio_no_CCS$improvement_to_2040
     
     bio_no_CCS_max_improv <- bio_no_CCS$max_improvement
     
     add_coal_and_bio <- existing_coal_bio %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                      units, X2015 ) %>% 
       dplyr::mutate( X2015 = dplyr::if_else( subsector.name == "coal", 
                                              X2015 / elec_IGCC_2015_cost_ratio$IGCC_CCS_no_CCS_2015_ratio,
                              dplyr::if_else( subsector.name == "biomass", 
                                              X2015 * elec_IGCC_2015_cost_ratio$IGCC_CCS_no_CCS_2015_ratio,
                                              NA_real_ ) ),
                      technology = dplyr::if_else( subsector.name == "coal", 
                                                   "coal chemical",
                                   dplyr::if_else( subsector.name == "biomass", 
                                                  "biomass to H2 CCS", NA_character_ ) ),
#                     Set coal w/o CCS improvements equal to bio w/o CCS
                      improvement_to_2040 = dplyr::if_else( technology == "coal chemical",
                                                            bio_no_CCS_impro_2040, NA_real_ ), 
                      max_improvement = dplyr::if_else( technology == "coal chemical",
                                                         bio_no_CCS_max_improv, NA_real_ ),
                      X2040 = dplyr::if_else( technology == "coal chemical", 
                                              X2015 * ( 1 - improvement_to_2040 ), NA_real_ ) )
       
     H2A_NE_cost_add_2015_techs <- H2A_NE_cost_conv_units %>%
       dplyr::filter( !( technology %in% c( "coal chemical", "biomass to H2 CCS" ) ) ) %>% 
       dplyr::bind_rows( add_coal_and_bio )
     
# C. Add nuclear max improvement, leveraging power sector
     H2A_NE_cost_add_nuclear <- H2A_NE_cost_add_2015_techs %>% 
       dplyr::mutate( max_improvement = dplyr::if_else( technology == "thermal splitting",
                                                        elec_nuclear_cost_improvement$max_improvement,
                                                        max_improvement ) )
     
# D. Extend assumptions to cover all GCAM years
      H2A_missing_Xyears_cols <- matrix ( NA_real_, 
                                          nrow = nrow( H2A_NE_cost_add_nuclear ), 
                                          ncol = length( H2A_missing_Xyears ), 
                                          dimnames = list( NULL, H2A_missing_Xyears ) )
      
      H2A_NE_cost_GCAM_years <- H2A_NE_cost_add_nuclear %>% 
        dplyr::bind_cols( as.data.frame( H2A_missing_Xyears_cols ) ) %>% 
        dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                       units, GCAM_H2_input_Xyears, improvement_to_2040, max_improvement ) %>% 
        dplyr::mutate( X1971 = X2015 ) %>%
        dplyr::mutate( improvement_rate = ( 1 - 
                                              ( ( X2040 / X2015 ) ^ 
                                              ( 1 / ( ( 2040 - 2015 ) / 5 ) )
                                             ) ) ) %>% 
        dplyr::mutate( X2020 = X2015 * ( 1 - improvement_rate ) ) %>% 
        dplyr::mutate( X2025 = X2020 * ( 1 - improvement_rate ) ) %>% 
        dplyr::mutate( X2030 = X2025 * ( 1 - improvement_rate ) ) %>% 
        dplyr::mutate( X2035 = X2030 * ( 1 - improvement_rate ) ) %>% 
        dplyr::mutate( X2040 = X2035 * ( 1 - improvement_rate ) ) %>% 
        
        dplyr::mutate( X2045 = dplyr::if_else( 
                       ( X2040 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                         X2040 * ( 1 - improvement_rate ),
                       ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2050 = dplyr::if_else( 
                      ( X2045 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2045 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2055 = dplyr::if_else( 
                      ( X2050 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2050 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>%  
        dplyr::mutate( X2060 = dplyr::if_else( 
                      ( X2055 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2055 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>%  
        dplyr::mutate( X2065 = dplyr::if_else( 
                      ( X2060 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2060 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>%  
        dplyr::mutate( X2070 = dplyr::if_else( 
                      ( X2065 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2065 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2075 = dplyr::if_else( 
                      ( X2070 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2070 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2080 = dplyr::if_else( 
                      ( X2075 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2075 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2085 = dplyr::if_else( 
                      ( X2080 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2080 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2090 = dplyr::if_else( 
                      ( X2085 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2085 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
        dplyr::mutate( X2095 = dplyr::if_else( 
                      ( X2090 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2090 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) ) %>% 
      dplyr::mutate( X2100 = dplyr::if_else( 
                      ( X2095 * ( 1 - improvement_rate ) ) >= ( X2015 * ( 1 - max_improvement ) ),
                        X2095 * ( 1 - improvement_rate ),
                      ( X2015 * ( 1 - max_improvement )  ) ) )
        

# E. Create bio + CCS and extend coal w/CCS
     ccs_costs <- add_coal_and_bio %>% 
        dplyr::select( -X2040, -improvement_to_2040, -max_improvement ) %>% 
        dplyr::bind_rows( existing_coal_bio %>% dplyr::select( -X2040, -improvement_to_2040, -max_improvement  ) ) %>% 
        tidyr::spread( technology, X2015 ) %>% 
        dplyr::mutate( X2015 = dplyr::if_else( subsector.name == "biomass",
                                                        !!rlang::sym( "biomass to H2 CCS" ) -
                                                        !!rlang::sym( "biomass to H2" ),
                                        dplyr::if_else( subsector.name == "coal",
                                                        !!rlang::sym( "coal chemical CCS" ) -
                                                        !!rlang::sym( "coal chemical" ),
                                                        NA_real_ ) ) ) %>% 
        dplyr::select(  sector.name, subsector.name, minicam.non.energy.input, units,
                        X2015 ) %>% 
#       Set bio's CCS tech to the same improvement rate as coal's, otherwise bio + CCS gets cheaper than coal + CCS
        dplyr::left_join( elec_IGCC_CCS_cost_improvement %>% 
                            dplyr::select( subsector.name, max_improvement ) %>% 
                            dplyr::filter( subsector.name == "coal" ) %>% 
                            dplyr::mutate( subsector.name = "biomass" ) %>% 
                            dplyr::bind_rows(  elec_IGCC_CCS_cost_improvement %>% 
                                                 dplyr::select( subsector.name, max_improvement ) %>% 
                                                 dplyr::filter( subsector.name == "coal" )  ),
                          by = "subsector.name" ) %>% 
        dplyr::mutate( X1971 = X2015,
                       X2100 = X2015  * ( 1 - max_improvement ),
                       improvement_rate = ( 1 - 
                                              ( ( X2100 / X2015 ) ^ 
                                                  ( 1 / ( ( 2100 - 2015 ) / 5 ) )
                                              ) ) ) %>% 
        dplyr::mutate( X2020 = dplyr::if_else( 
          ( X2015 * ( 1 - improvement_rate ) ) >= X2100,
          X2015 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2025 = dplyr::if_else( 
          ( X2020 * ( 1 - improvement_rate ) ) >= X2100,
          X2020 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2030 = dplyr::if_else( 
          ( X2025 * ( 1 - improvement_rate ) ) >= X2100,
          X2025 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2035 = dplyr::if_else( 
          ( X2030 * ( 1 - improvement_rate ) ) >= X2100,
          X2030 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2040 = dplyr::if_else( 
          ( X2035 * ( 1 - improvement_rate ) ) >= X2100,
          X2035 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2045 = dplyr::if_else( 
          ( X2040 * ( 1 - improvement_rate ) ) >= X2100,
          X2040 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2050 = dplyr::if_else( 
          ( X2045 * ( 1 - improvement_rate ) ) >= X2100,
          X2045 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2055 = dplyr::if_else( 
          ( X2050 * ( 1 - improvement_rate ) ) >= X2100,
          X2050 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2060 = dplyr::if_else( 
          ( X2055 * ( 1 - improvement_rate ) ) >= X2100,
          X2055 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2065 = dplyr::if_else( 
          ( X2060 * ( 1 - improvement_rate ) ) >= X2100,
          X2060 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2070 = dplyr::if_else( 
          ( X2065 * ( 1 - improvement_rate ) ) >= X2100,
          X2065 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2075 = dplyr::if_else( 
          ( X2070 * ( 1 - improvement_rate ) ) >= X2100,
          X2070 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2080 = dplyr::if_else( 
          ( X2075 * ( 1 - improvement_rate ) ) >= X2100,
          X2075 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2085 = dplyr::if_else( 
          ( X2080 * ( 1 - improvement_rate ) ) >= X2100,
          X2080 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2090 = dplyr::if_else( 
          ( X2085 * ( 1 - improvement_rate ) ) >= X2100,
          X2085 * ( 1 - improvement_rate ),
          X2100 ) ) %>% 
        dplyr::mutate( X2095 = dplyr::if_else( 
          ( X2090 * ( 1 - improvement_rate ) ) >= X2100,
          X2090 * ( 1 - improvement_rate ),
          X2100 ) ) 
      
#     Make bio + CCS tech (= bio tech + CCS cost adder)
      bio_w_ccs <- H2A_NE_cost_GCAM_years %>% 
        dplyr::filter( technology == "biomass to H2" ) %>% 
        dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input, 
                       units, GCAM_H2_input_Xyears ) %>% 
        dplyr::bind_rows( ccs_costs %>% 
                            dplyr::select( sector.name, subsector.name, minicam.non.energy.input, 
                                           units, GCAM_H2_input_Xyears ) %>% 
                            dplyr::filter( subsector.name == "biomass"  ) %>% 
                            dplyr::mutate( technology = "CCS_cost" ) ) %>% 
        tidyr::gather( key = year, value = variable_value, GCAM_H2_input_Xyears ) %>% 
        tidyr::spread( technology, variable_value ) %>% 
        dplyr::mutate( biomass_CCS = !!rlang::sym( "biomass to H2" ) + CCS_cost ) %>% 
        dplyr::select( -!!rlang::sym( "biomass to H2" ), -CCS_cost ) %>% 
        dplyr::mutate( technology = "biomass to H2 CCS" ) %>% 
        tidyr::spread( year, biomass_CCS )

#     Make coal + CCS tech (= coal tech + CCS cost adder)
      coal_w_CCS <- H2A_NE_cost_GCAM_years %>% 
        dplyr::filter( technology == "coal chemical" ) %>% 
        dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input, 
                       units, GCAM_H2_input_Xyears ) %>% 
        dplyr::bind_rows( ccs_costs %>% 
                            dplyr::select( sector.name, subsector.name, minicam.non.energy.input, 
                                           units, GCAM_H2_input_Xyears ) %>% 
                            dplyr::filter( subsector.name == "coal"  ) %>% 
                            dplyr::mutate( technology = "CCS_cost" ) ) %>% 
        tidyr::gather( key = year, value = variable_value, GCAM_H2_input_Xyears ) %>% 
        tidyr::spread( technology, variable_value ) %>% 
        dplyr::mutate( coal_CCS = !!rlang::sym( "coal chemical" ) + CCS_cost ) %>% 
        dplyr::select( -!!rlang::sym( "coal chemical" ), -CCS_cost ) %>% 
        dplyr::mutate( technology = "coal chemical CCS" ) %>% 
        tidyr::spread( year, coal_CCS )
      
#     Join the bio and coal CCS techs with the rest of the data
      H2A_NE_add_missing_techs <- H2A_NE_cost_GCAM_years %>% 
        dplyr::filter( !( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ) ) ) %>% 
        dplyr::bind_rows( bio_w_ccs, coal_w_CCS ) %>% 
#       Calculations to check extension
        dplyr::mutate( improvement_to_2040_check  = ( 1 - ( X2040 / X2015 ) ) ) %>% 
        dplyr::mutate( check_2040 = dplyr::if_else( round( improvement_to_2040 , 8 ) == round( improvement_to_2040_check, 8 ),
                                                    TRUE, FALSE ) ) %>% 
        dplyr::mutate( max_improvement_check = ( 1 - ( X2100 / X2015 ) ) ) %>% 
        dplyr::mutate( check_2100 = dplyr::if_else( max_improvement >= round( max_improvement_check, 2 ),
                                                    TRUE, FALSE ) )  %>% 
#       Set to true for technologies which were created
        dplyr::mutate( check_2040 = dplyr::if_else( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ),
                                                    TRUE, check_2040 ),
                       check_2100 = dplyr::if_else( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ),
                                                    TRUE, check_2100 ) )

      
# F. Check extension values
      if( any( H2A_NE_cost_GCAM_years$check_2040 == FALSE ) ){

        stop( "One or more technologies have an improvement to 2040 which is not equal to NREL H2A's improvment to 2040 for cost data..." )

      }
      
      if( any( H2A_NE_cost_GCAM_years$check_2100 == FALSE ) ){

        stop( "One or more technologies have an improvement to 2100 which is larger than the specified max improvement rate for cost data..." )

      }
      
# G. Final data cleaning
      print( paste0( "Final GCAM H2 production non-energy cost units: ", 
                     unique( H2A_NE_add_missing_techs$units ) ) )
      
     GCAM_H2_prod_NE_cost <- H2A_NE_add_missing_techs %>% 
        dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                       GCAM_H2_input_Xyears ) %>% 
        dplyr::rename_at( .vars = GCAM_H2_input_Xyears,
                          .funs = remove_X_years ) %>% 
        dplyr::arrange( sector.name, subsector.name, technology )
     
# ------------------------------------------------------------------------------
# VI. Process coef data for each H2A technology
    
# A. Combine all inputs into one energy requirement
     if( multiple_inputs == FALSE ){
       
#        1.) Conversion from electricity to "feedstock" ( = elec requirement * 3 )
         H2A_coef_elec_sum <- H2A_coef %>% 
           dplyr::rename( "X2015" = "2015", 
                          "X2040" = "2040" ) %>% 
           dplyr::mutate( X2015 = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                  units == "GJ in /kg H2 out",
                                                  X2015 *  GJ_fuel_per_GJ_elec,
                                                  X2015 ),
                          X2040 = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                  units == "GJ in /kg H2 out",
                                                  X2040 *  GJ_fuel_per_GJ_elec,
                                                  X2040 ),
                          minicam.non.energy.input = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                                     technology %in% c( "biomass to H2", "biomass to H2 CCS" ),
                                                                     "regional biomass", minicam.non.energy.input ),
                          minicam.non.energy.input = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                                     technology %in% c( "coal chemical", "coal chemical CCS" ),  
                                                                     "regional coal", minicam.non.energy.input ),
                          minicam.non.energy.input = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                                     technology %in% c( "natural gas steam reforming", "natural gas steam reforming CCS" ) &
                                                                     sector.name == "H2 central production",
                                                                     "regional natural gas", minicam.non.energy.input ),
                          minicam.non.energy.input = dplyr::if_else( minicam.non.energy.input == "elect_td_ind" &
                                                                     technology == "natural gas steam reforming" &
                                                                     sector.name == "H2 forecourt production",
                                                                     "delivered gas", minicam.non.energy.input ) ) %>% 
          dplyr::select( -notes ) %>% 
          dplyr::group_by( sector.name, subsector.name, technology, minicam.non.energy.input, units ) %>% 
          dplyr::summarize_all( funs( sum( . ) ) ) %>% 
          dplyr::ungroup( )
       
#        2.) Conversion from NG to bio (using GCAM biomass gas eff.)
         H2A_coef_ng_sum <- H2A_coef_elec_sum %>% 
           dplyr::mutate( X2015 = dplyr::if_else( minicam.non.energy.input == "regional natural gas" &
                                                  subsector.name == "biomass",
                                                  X2015 *  GJ_bio_per_GJ_bio_gas,
                                                  X2015 ),
                          X2040 = dplyr::if_else( minicam.non.energy.input == "regional natural gas" &
                                                  subsector.name == "biomass",
                                                  X2040 *  GJ_bio_per_GJ_bio_gas,
                                                  X2040 ),
                          minicam.non.energy.input = dplyr::if_else( minicam.non.energy.input == "regional natural gas" &
                                                                     subsector.name == "biomass",
                                                                     "regional biomass", minicam.non.energy.input ) ) %>%           
            dplyr::group_by( sector.name, subsector.name, technology, minicam.non.energy.input, units ) %>% 
            dplyr::summarize_all( funs( sum( . ) ) ) %>% 
            dplyr::ungroup( )                             
                                                                                        
       H2A_coef_reformatted <- H2A_coef_ng_sum                                                         
                                                  
     } else {

       H2A_coef_reformatted <- H2A_coef %>% 
         dplyr::rename( "X2015" = "2015", 
                        "X2040" = "2040" ) %>% 
          dplyr::select( -notes ) 

     }
     
# B. Convert Units: 
#    From: GJ in / kg H2 out 
#    To:   GJ H2 out / GJ in )
     H2A_eff <- H2A_coef_reformatted %>% 
       dplyr::mutate( X2015 = dplyr::if_else( units == "GJ in /kg H2 out",
                                             ( ( X2015 / GJ_per_kgH2 ) ^ -1),
                                             X2015 ),
                      X2040 = dplyr::if_else( units == "GJ in /kg H2 out",
                                              ( ( X2040 / GJ_per_kgH2 ) ^ -1),
                                              X2040 ),
                      units = dplyr::if_else( units == "GJ in /kg H2 out",
                                              "GJ hydrogen output / GJ input",
                                              units ) )
                    
# C. Without doing the efficiency for NG and electricity independently for the 'natural gas steam reforming'
#    technology, the efficiency for the NG input actually goes down by 2040 (electricity converted to NG).
#    Set NG SMR (forecourt and central) 2040 efficiency to 2015, slow improvement afterwards.
#    TODO: J - This may not be necessary if efficiency shows improvement when the different inputs are read
#                in separately, so I've added an if() statement for now.
     if( multiple_inputs == FALSE ){
       
       H2A_eff_fix_NG <- H2A_eff %>% 
         dplyr::mutate( X2040 = dplyr::if_else( technology  == "natural gas steam reforming",
                                                X2015, X2040 ) )
       
     } else{
       
       H2A_eff_fix_NG <- H2A_eff

     }

# D. Calculate improvement between 2015 and 2040
     H2A_eff_improvement <- H2A_eff_fix_NG %>% 
        dplyr::mutate( improvement_to_2040 = ( ( X2040 - X2015 ) / X2015 ), 
#    Set improvement rate
                       improvement_rate = ( ( ( X2040 / X2015 ) ^ 
                                                ( 1 / ( ( 2040 - 2015 ) / 5 ) ) ) 
                                            - 1 ) )
#    TODO: J - You'll want to make sure you have improvement rates for the non-feedstock inputs (elec and NG for bio)
     
# E. Add X2015 value for coal w/o CCS and bio w/CCS
     existing_coal_bio_eff <- H2A_eff_improvement %>% 
       dplyr::filter( technology %in% c( "biomass to H2", "coal chemical CCS" ) )
     
     bio_no_CCS_eff <- existing_coal_bio_eff %>% 
       dplyr::filter( technology == "biomass to H2" ) 
     
     bio_no_CCS_improv_2040_eff <- bio_no_CCS_eff$improvement_to_2040
     bio_no_CCS_improv_rate <- bio_no_CCS_eff$improvement_rate
     
     add_coal_and_bio_eff <- existing_coal_bio_eff %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                      units, X2015 ) %>% 
       dplyr::mutate( X2015 = dplyr::if_else( subsector.name == "coal", 
                                              X2015 / elec_IGCC_2015_eff_ratio_coal$IGCC_CCS_no_CCS_2015_ratio,
                              dplyr::if_else( subsector.name == "biomass", 
                                              X2015 * elec_IGCC_2015_eff_ratio_bio$IGCC_CCS_no_CCS_2015_ratio,
                                              NA_real_ ) ),
                      technology = dplyr::if_else( subsector.name == "coal", 
                                                   "coal chemical",
                                   dplyr::if_else( subsector.name == "biomass", 
                                                   "biomass to H2 CCS", NA_character_ ) ),
#                     Set coal w/o CCS improvement equal to bio w/o CCS
                      improvement_to_2040 = dplyr::if_else( technology == "coal chemical",
                                                            bio_no_CCS_improv_2040_eff, NA_real_ ), 
                      improvement_rate = dplyr::if_else( technology == "coal chemical",
                                                         bio_no_CCS_improv_rate, NA_real_ ), 
                      X2040 = dplyr::if_else( technology == "coal chemical", 
                                              X2015 * ( 1 - improvement_to_2040 ), NA_real_ ) )
     
     H2A_eff_add_2015_techs <- H2A_eff_improvement %>%
       dplyr::filter( !( technology %in% c( "coal chemical", "biomass to H2 CCS" ) ) ) %>% 
       dplyr::bind_rows( add_coal_and_bio_eff ) %>% 
#      Max improvement of efficiency currently set to 10% improvement beyond improvement to 2040, 
#      relative to 2015
       dplyr::mutate( max_improvement = round( improvement_to_2040 + 0.1, 2 ) ) %>% 
#      Nuclear max improvement set to 0
       dplyr::mutate( max_improvement = dplyr::if_else( subsector.name == "nuclear", 0, max_improvement ) ) %>% 
#     Coal w/o CCS max improvement set to 7.5%
       dplyr::mutate( max_improvement = dplyr::if_else( technology == "coal chemical", 0.075, max_improvement ) )
     
      central_elec_eff_max_imrpov <- H2A_eff_add_2015_techs %>% 
         dplyr::filter( sector.name == "H2 central production" &
                        subsector.name == "electricity" ) 
     
      central_elec_eff_max_imrpov <- central_elec_eff_max_imrpov$max_improvement
       
     H2A_eff_fix_improv <- H2A_eff_add_2015_techs %>% 
#      Forecourt electrolysis max improvement = central electrolysis max improvement - 1%
       dplyr::mutate( max_improvement = dplyr::if_else( sector.name == "H2 forecourt production" &
                                                        subsector.name == "electricity", 
                                                        central_elec_eff_max_imrpov - 0.01, 
                                                        max_improvement ) ) %>% 
#      Set improvement rate post 2040 to pre-2040 improvement
       dplyr::mutate( improvement_rate_post_2040 = improvement_rate ) %>% 
#      Post 2040 improvement rate for central NG w/ and w/o CCS set to 0.3%
       dplyr::mutate( improvement_rate_post_2040 = dplyr::if_else( sector.name == "H2 central production" &
                                                                   technology %in% c( "natural gas steam reforming",
                                                                                     "natural gas steam reforming CCS" ),
                                                                   0.003, improvement_rate_post_2040 ) ) %>% 
#      Post 2040 improvement rate for forecourt NG wset to 0.45%
       dplyr::mutate( improvement_rate_post_2040 = dplyr::if_else( sector.name == "H2 forecourt production" &
                                                                   technology == "natural gas steam reforming",
                                                                   0.0045, improvement_rate_post_2040 ) ) 
       
# F. Extend assumptions to cover all GCAM years
     H2A_eff_GCAM_years <- H2A_eff_fix_improv %>% 
       dplyr::bind_cols( as.data.frame( H2A_missing_Xyears_cols ) ) %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                      units, GCAM_H2_input_Xyears, improvement_to_2040, improvement_rate, improvement_rate_post_2040, max_improvement ) %>% 
       dplyr::mutate( X1971 = X2015 ) %>%
       
       dplyr::mutate( X2020 = X2015 * ( 1 + improvement_rate ) ) %>% 
       dplyr::mutate( X2025 = X2020 * ( 1 + improvement_rate ) ) %>% 
       dplyr::mutate( X2030 = X2025 * ( 1 + improvement_rate ) ) %>% 
       dplyr::mutate( X2035 = X2030 * ( 1 + improvement_rate ) ) %>% 
       dplyr::mutate( X2040 = X2035 * ( 1 + improvement_rate ) ) %>% 
       
#      Improvement beyond 2040 allowed, unless it exceeds the maximum improvement assumed above
       dplyr::mutate( X2045 = dplyr::if_else( 
         ( X2040 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2040 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2050 = dplyr::if_else( 
         ( X2045 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2045 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2055 = dplyr::if_else( 
         ( X2050 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2050 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2060 = dplyr::if_else( 
         ( X2055 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2055 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2065 = dplyr::if_else( 
         ( X2060 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2060 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2070 = dplyr::if_else( 
         ( X2065 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2065 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2075 = dplyr::if_else( 
         ( X2070 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2070 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2080 = dplyr::if_else( 
         ( X2075 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2075 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2085 = dplyr::if_else( 
         ( X2080 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2080 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2090 = dplyr::if_else( 
         ( X2085 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2085 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2095 = dplyr::if_else( 
         ( X2090 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2090 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::mutate( X2100 = dplyr::if_else( 
         ( X2095 * ( 1 + improvement_rate_post_2040 )  ) <= ( X2015 * ( 1 + max_improvement ) ),
         X2095 * ( 1 + improvement_rate_post_2040 ),
         ( X2015 * ( 1 + max_improvement )  ) ) ) %>% 
       
       dplyr::select( -improvement_rate_post_2040 )
     
# G. Create bio + CCS and extend coal w/CCS
#    TODO: J - You'll want to make sure this works for the non-feedstock inputs (elec and NG for bio)
     ccs_eff <- add_coal_and_bio_eff %>% 
       dplyr::select( -X2040, -improvement_to_2040, -improvement_rate ) %>% 
       dplyr::bind_rows( existing_coal_bio_eff %>% dplyr::select( -X2040, -improvement_to_2040, -improvement_rate  ) ) %>% 
       tidyr::spread( technology, X2015 ) %>% 
#      Calculate efficiency loss from carbon capture in 2015
       dplyr::mutate( X2015 = dplyr::if_else( subsector.name == "biomass",
                                              !!rlang::sym( "biomass to H2 CCS" ) -
                                              !!rlang::sym( "biomass to H2" ),
                              dplyr::if_else( subsector.name == "coal",
                                              !!rlang::sym( "coal chemical CCS" ) -
                                              !!rlang::sym( "coal chemical" ),
                                              NA_real_ ) ) ) %>% 
       dplyr::select(  sector.name, subsector.name, minicam.non.energy.input, units,
                       X2015 ) %>% 
#     Set improvement rate for the efficiency loss based on CCS efficiency loss in the power sector
       dplyr::left_join( elec_IGCC_CCS_eff_improvement %>% 
                           dplyr::select( subsector.name, max_improvement ),
                           by = "subsector.name" ) %>% 
       dplyr::mutate( X1971 = X2015,
                      X2100 = X2015  * ( 1 - max_improvement ),
                      improvement_rate = ( ( ( X2100 / X2015 ) ^ 
                                               ( 1 / ( ( 2100 - 2015 ) / 5 ) ) ) 
                                           - 1 ) ) %>% 
       dplyr::mutate( X2020 = dplyr::if_else( 
         ( X2015 * ( 1 + improvement_rate ) ) <= X2100,
         X2015 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2025 = dplyr::if_else( 
         ( X2020 * ( 1 + improvement_rate ) ) <= X2100,
         X2020 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2030 = dplyr::if_else( 
         ( X2025 * ( 1 + improvement_rate ) ) <= X2100,
         X2025 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2035 = dplyr::if_else( 
         ( X2030 * ( 1 + improvement_rate ) ) <= X2100,
         X2030 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2040 = dplyr::if_else( 
         ( X2035 * ( 1 + improvement_rate ) ) <= X2100,
         X2035 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2045 = dplyr::if_else( 
         ( X2040 * ( 1 + improvement_rate ) ) <= X2100,
         X2040 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2050 = dplyr::if_else( 
         ( X2045 * ( 1 + improvement_rate ) ) <= X2100,
         X2045 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2055 = dplyr::if_else( 
         ( X2050 * ( 1 + improvement_rate ) ) <= X2100,
         X2050 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2060 = dplyr::if_else( 
         ( X2055 * ( 1 + improvement_rate ) ) <= X2100,
         X2055 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2065 = dplyr::if_else( 
         ( X2060 * ( 1 + improvement_rate ) ) <= X2100,
         X2060 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2070 = dplyr::if_else( 
         ( X2065 * ( 1 + improvement_rate ) ) <= X2100,
         X2065 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2075 = dplyr::if_else( 
         ( X2070 * ( 1 + improvement_rate ) ) <= X2100,
         X2070 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2080 = dplyr::if_else( 
         ( X2075 * ( 1 + improvement_rate ) ) <= X2100,
         X2075 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2085 = dplyr::if_else( 
         ( X2080 * ( 1 + improvement_rate ) ) <= X2100,
         X2080 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2090 = dplyr::if_else( 
         ( X2085 * ( 1 + improvement_rate ) ) <= X2100,
         X2085 * ( 1 + improvement_rate ),
         X2100 ) ) %>% 
       dplyr::mutate( X2095 = dplyr::if_else( 
         ( X2090 * ( 1 + improvement_rate ) ) <= X2100,
         X2090 * ( 1 + improvement_rate ),
         X2100 ) ) 
    
#    Create bio + CCS technology (bio tech + CCS efficiency loss)
#    TODO: J - You'll want to make sure this works for the non-feedstock inputs (elec and NG for bio)
     bio_w_ccs_eff <- H2A_eff_GCAM_years %>% 
       dplyr::filter( technology == "biomass to H2" ) %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input, 
                      units, GCAM_H2_input_Xyears ) %>% 
       dplyr::bind_rows( ccs_eff %>% 
                           dplyr::select( sector.name, subsector.name, minicam.non.energy.input, 
                                          units, GCAM_H2_input_Xyears ) %>% 
                           dplyr::filter( subsector.name == "biomass"  )  %>% 
                           dplyr::mutate( technology = "CCS_eff_loss" ) ) %>% 
       tidyr::gather( key = year, value = variable_value, GCAM_H2_input_Xyears ) %>% 
       tidyr::spread( technology, variable_value ) %>% 
       dplyr::mutate( biomass_CCS = !!rlang::sym( "biomass to H2" ) + CCS_eff_loss ) %>% 
       dplyr::select( -!!rlang::sym( "biomass to H2" ), -CCS_eff_loss ) %>% 
       dplyr::mutate( technology = "biomass to H2 CCS" ) %>% 
       tidyr::spread( year, biomass_CCS )
     
#    Create coal + CCS technology (coal tech + CCS efficiency loss)
#    TODO: J - You'll want to make sure this works for the non-feedstock inputs (elec and NG for bio)
     coal_w_CCS_eff <- H2A_eff_GCAM_years %>% 
       dplyr::filter( technology == "coal chemical" ) %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input, 
                      units, GCAM_H2_input_Xyears ) %>% 
       dplyr::bind_rows( ccs_eff %>% 
                           dplyr::select( sector.name, subsector.name, minicam.non.energy.input, 
                                          units, GCAM_H2_input_Xyears ) %>% 
                           dplyr::filter( subsector.name == "coal"  )  %>% 
                           dplyr::mutate( technology = "CCS_eff_loss" ) ) %>% 
       tidyr::gather( key = year, value = variable_value, GCAM_H2_input_Xyears ) %>% 
       tidyr::spread( technology, variable_value ) %>% 
       dplyr::mutate( coal_CCS = !!rlang::sym( "coal chemical" ) + CCS_eff_loss ) %>% 
       dplyr::select( -!!rlang::sym( "coal chemical" ), -CCS_eff_loss ) %>% 
       dplyr::mutate( technology = "coal chemical CCS" ) %>% 
       tidyr::spread( year, coal_CCS )
     
#    Add coal and biomass + CCS techs to data
     H2A_eff_add_missing_techs <- H2A_eff_GCAM_years %>% 
       dplyr::filter( !( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ) ) ) %>% 
       dplyr::bind_rows( bio_w_ccs_eff, coal_w_CCS_eff ) %>% 
#      Calculations to check extension
       dplyr::mutate( improvement_to_2040_check  = ( ( 1 - ( X2040 / X2015 ) ) * -1 ) ) %>% 
       dplyr::mutate( check_2040 = dplyr::if_else( round( improvement_to_2040 , 8 ) == round( improvement_to_2040_check, 8 ),
                                                   TRUE, FALSE ) ) %>% 
       dplyr::mutate( max_improvement_check = ( ( 1 - ( X2100 / X2015 ) ) * -1 ) ) %>% 
       dplyr::mutate( check_2100 = dplyr::if_else( round( max_improvement, 8) >= round( max_improvement_check, 8 ),
                                                   TRUE, FALSE ) )  %>% 
#      Set to true for technologies which were created
       dplyr::mutate( check_2040 = dplyr::if_else( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ),
                                                   TRUE, check_2040 ),
                      check_2100 = dplyr::if_else( technology %in% c( "biomass to H2 CCS", "coal chemical CCS" ),
                                                   TRUE, check_2100 ) )
     
# H. Check extension values
     if( any( H2A_eff_add_missing_techs$check_2040 == FALSE ) ){
       
       stop( "One or more technologies have an improvement to 2040 which is not equal to NREL H2A's improvment to 2040 for eff. data..." )
       
     }
     
     if( any( H2A_eff_add_missing_techs$check_2100 == FALSE ) ){
       
       stop( "One or more technologies have an improvement to 2100 which is larger than the specified max improvement rate for eff. data..." )
       
     }
     
# I. Final data cleaning
     print( paste0( "Final GCAM H2 production efficiency units: ", 
                    unique( H2A_eff_add_missing_techs$units ) ) )
     
     GCAM_H2_prod_eff <- H2A_eff_add_missing_techs %>% 
       dplyr::select( sector.name, subsector.name, technology, minicam.non.energy.input,
                      GCAM_H2_input_Xyears ) %>% 
       dplyr::rename_at( .vars = GCAM_H2_input_Xyears,
                         .funs = remove_X_years ) %>% 
       dplyr::arrange( sector.name, subsector.name, technology )

# ------------------------------------------------------------------------------
# VII. Write outputs

#   A. Set wd to output directory
    setwd( "../output" )
     
#   B. Costs:
    write.csv( GCAM_H2_prod_NE_cost, "A25.globaltech_cost-no_header_no_dis.csv", row.names = FALSE )
     
#   C. Efficiencies:
    write.csv( GCAM_H2_prod_eff, "A25.globaltech_eff-no_header_no_dis.csv", row.names = FALSE )
     
# END

   
