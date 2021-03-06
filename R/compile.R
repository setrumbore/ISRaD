#' Compile ISRaD data product
#'
#' Construct data products to the International Soil Radiocarbon Database.
#'
#' @param dataset_directory string defining directory where compeleted and
#' QC passed soilcarbon datasets are stored
#' @param write_report boolean flag to write a log file of the
#' compilation (FALSE will dump output to console). File will be in the specified
#' in the dataset_directory at "database/ISRaD_log.txt". If there is a file already
#' there of this name it will be overwritten.
#' @param write_out boolean flag to write the compiled database file as csv
#' in dataset_directory (FALSE will not generate ouput file but will return)
#' @param return_type a string that defines return object.
#' Default is "none".
#' Acceptable values are "flat" or "list" depending on the format you want to
#' have the database returned in.
#'
#' @export
#'
#' @import devtools
#' @import dplyr
#' @import stringi
#' @import openxlsx
#' @import dplyr
#' @import tidyr
#' @import assertthat
#'

compile <- function(dataset_directory,
                    write_report=FALSE, write_out=FALSE,
                    return_type=c('none', 'list', 'flat')[1]){
  #Libraries used
  requireNamespace("stringi")
  requireNamespace("assertthat")
  requireNamespace("openxlsx")
  requireNamespace("dplyr")
  requireNamespace("tidyr")

  # Check inputs
  assertthat::assert_that(dir.exists(dataset_directory))
  assertthat::assert_that(is.logical(write_report))
  assertthat::assert_that(is.logical(write_out))
  assertthat::assert_that(is.character(return_type))

  #Create directories
  if(! dir.exists(file.path(dataset_directory, "QAQC"))){
    dir.create(file.path(dataset_directory, "QAQC")) #Creates folder for QAQC reports
  }
  if(! dir.exists(file.path(dataset_directory, "database"))){
    dir.create(file.path(dataset_directory, "database")) #creates folder for final output dump
  }

  #Set output file
  outfile <- ""
  if(write_report){
    outfile <- file.path(dataset_directory, "database", "ISRaD_log.txt")
  }

  #Start writing in the output file
  cat("ISRaD Compilation Log \n",
      "\n", as.character(Sys.time()),
      "\n",rep("-", 15),"\n", file=outfile)


# Check template and info compatability -------------------------------------------------
  checkTempletFiles(outfile)

# QAQC and compile data files -------------------------------------------------------
  # Get the tables stored in the templet sheets
  template_file <- system.file("extdata", "ISRaD_Master_Template.xlsx",
                               package = "ISRaD")
  template <- lapply(setNames(nm=openxlsx::getSheetNames(template_file)),
                     function(s){openxlsx::read.xlsx(template_file,
                                                     sheet=s)})

  template_nohead <- lapply(template, function(x) x[-c(1,2),])
  template_flat <- Reduce(function(...) merge(..., all=TRUE), template_nohead)
  flat_template_columns <- colnames(template_flat)

  working_database <- template_flat %>% mutate_all(as.character)
  ISRaD_database <- lapply(template[1:8], function(x) x[-c(1,2),])
  ISRaD_database <- lapply(ISRaD_database, function(x) x %>% mutate_all(as.character))

  cat("\n\nCompiling data files in", dataset_directory, "\n", rep("-", 30),"\n",
      file=outfile, append = TRUE)

  data_files<-list.files(dataset_directory, full.names = TRUE)
  data_files<-data_files[grep("xlsx", data_files)]

  entry_stats<-data.frame()

  for(d in 1:length(data_files)){
    cat("\n\n",d, "checking", basename(data_files[d]),"...",
        file=outfile, append = TRUE)
    soilcarbon_data<-QAQC(file = data_files[d], writeQCreport = TRUE, dataReport = TRUE)
    if (attributes(soilcarbon_data)$error>0) {
      cat("failed QAQC. Check report in QAQC folder.", file=outfile, append = TRUE)
      next
    } else cat("passed", file=outfile, append = TRUE)


   char_data <- lapply(soilcarbon_data, function(x) x %>% mutate_all(as.character))

   #data_stats<-bind_cols(data.frame(entry_name=char_data$metadata$entry_name, doi=char_data$metadata$doi), as.data.frame(lapply(char_data, nrow)))
   #data_stats<- data_stats %>% mutate_all(as.character)
   #entry_stats<-bind_rows(entry_stats, data_stats)

    flat_data<-char_data %>%
    Reduce(function(dtf1,dtf2) full_join(dtf1,dtf2), .)
    working_database<-bind_rows(working_database, flat_data)

  for (t in 1:length(char_data)){
    tab<-colnames(char_data)[t]
    data_tab<-char_data[[t]]
    ISRaD_database[[t]]<-bind_rows(ISRaD_database[[t]], data_tab)
  }

}

  working_database[]<-lapply(working_database, function(x)
    stringi::stri_trans_general(x, "latin-ascii"))
  working_database[]<-lapply(working_database, type.convert)
  soilcarbon_database<-working_database

# Return database file, logs, and reports ---------------------------------
  cat("\n\n-------------\n", file=outfile, append = T)
  cat("\nSummary statistics...\n", file=outfile, append = T)

  for (t in 1:length(names(ISRaD_database))){
    tab<-names(ISRaD_database)[t]
    data_tab<-ISRaD_database[[tab]]
    cat("\n",tab,"tab...", file=outfile, append = T)
    cat(nrow(data_tab), "observations", file=outfile, append = T)
    if (nrow(data_tab)>0){
      col_counts<-apply(data_tab, 2, function(x) sum(!is.na(x)))
      col_counts<-col_counts[col_counts>0]
      for(c in 1:length(col_counts)){
        cat("\n   ", names(col_counts[c]),":", col_counts[c], file=outfile, append = T)

      }
    }
  }

  ISRaD_database_excel<-list()
  ISRaD_database_excel$metadata<-rbind(template$metadata,ISRaD_database$metadata)
  ISRaD_database_excel$site<-rbind(template$site,ISRaD_database$site)
  ISRaD_database_excel$profile<-rbind(template$profile,ISRaD_database$profile)
  ISRaD_database_excel$flux<-rbind(template$flux,ISRaD_database$flux)
  ISRaD_database_excel$layer<-rbind(template$layer,ISRaD_database$layer)
  ISRaD_database_excel$interstitial<-rbind(template$interstitial,ISRaD_database$interstitial)
  ISRaD_database_excel$fraction<-rbind(template$fraction,ISRaD_database$fraction)
  ISRaD_database_excel$incubation<-rbind(template$incubation,ISRaD_database$incubation)
  ISRaD_database_excel$`controlled vocabulary`<-template$`controlled vocabulary`



  openxlsx::write.xlsx(ISRaD_database_excel, file = file.path(dataset_directory, "database", "ISRaD_list.xlsx"))
  #QAQC(file.path(dataset_directory, "database", "ISRaD_list.xlsx"),
  #     writeQCreport = TRUE,
  #     outfile = file.path(dataset_directory, "database", "QAQC_ISRaD_list.txt"))

  #write.csv(entry_stats, paste0(dataset_directory, "database/ISRaD_summary.csv"))

  cat("\n", rep("-", 20), file=outfile, append = TRUE)

  if (write_out==TRUE){
    write.csv(soilcarbon_database, file.path(dataset_directory, "database", "ISRaD_flat.csv"))
  }

    cat("\n Compilation report saved to", outfile,"\n", file="", append = T)

    if(return_type=="list"){
  return(ISRaD_database)
    }
    if(return_type=="flat"){
      return(soilcarbon_database)
    }


}
