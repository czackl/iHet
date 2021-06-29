#!/usr/bin/env nextflow

nextflow.enable.dsl = 2
include { nxfvars; file_tuple } from "./nxfvars.nf"

process P11_easier {
    publishDir "${params.result_dir}/10_mofa/${id}", mode: params.publish_dir_mode 
    // conda "/data/scratch/sturm/conda/envs/2021-nsclc_heterogeneity-easier"
    container "containers/2021-nsclc_heterogeneity-easier.sif"
    input: 
        tuple val(id), path(script)
        path(expr_data)
    
    output:
        path("*.features.rds")

    """
    Rscript ${script} \\
        ${expr_data} \\
        ${baseDir}/tables/easier_Zscores/immscoreZ.rds \\
        ${expr_data.baseName}.features.rds 
    """
}

process P12_prepare_mofa_data {
    publishDir "${params.result_dir}/10_mofa/${id}", mode: params.publish_dir_mode 
    conda "/data/scratch/sturm/conda/envs/2021-nsclc_heterogeneity-mofa"
    cpus 1
    input:
        tuple val(id), path(notebook)
        path(datasets)

    output:
        path("*.html"), emit: report
        path("datasets/mofa_*.rds"), emit: mofa_datasets 
        path("datasets/data_all_tidy.rds"), emit: data_all

    script:
    data_dir = "./"
    out_dir = "datasets"
    """
    ${nxfvars(task)}
    execute_rmd.r ${notebook}
    """
}

process P13_run_mofa {
    publishDir "${params.result_dir}/10_mofa/${id}", mode: params.publish_dir_mode 
    conda "/data/scratch/sturm/conda/envs/2021-nsclc_heterogeneity-mofa"
    cpus 1
    input:
        tuple val(id), path(script)
        each path(dataset)

    output:
        path("*.hdf5"), emit: models 

    script:
    """
    Rscript ${script} ${dataset}
    """
}

process P14_mofa_analysis {
    publishDir "${params.result_dir}/10_mofa/${id}", mode: params.publish_dir_mode 
    conda "/data/scratch/sturm/conda/envs/2021-nsclc_heterogeneity-mofa"
    cpus 1
    input:
        tuple val(id), path(notebook)
        path("helper_functions.R")
        path(easier_data)
        path(features)
        path(models)
        path(tmb_data)

    output:
        path("*.html"), emit: report
        path("*.{tsv,rds}"), emit: tables
        path("plots/*.*"), emit: figures

    script:
    data_dir = "./"
    features_dir = "./"
    easier_dir = "./"
    out_dir = "./"
    tmb_dir = "./"
    """
    ${nxfvars(task)}
    execute_rmd.r ${notebook}
    """
}


workflow W10_mofa {
    def dir = "analyses/10_mofa"
    P11_easier(
        file_tuple("$dir/11_easier.R"),
        Channel.fromPath("data/01_processed/bulk_rna_seq/*_expr_data*.rds")
    )
    P12_prepare_mofa_data(
        file_tuple("$dir/12_prepare_mofa_data.Rmd"),
        P11_easier.out.collect()
    )
    P13_run_mofa(
        file_tuple("$dir/13_run_mofa.R"),
        P12_prepare_mofa_data.out.mofa_datasets
    )
    P14_mofa_analysis(
        file_tuple("$dir/14_mofa_analysis.Rmd"),
        file("$dir/helper_functions.R"),
        P11_easier.out.collect(),
        P12_prepare_mofa_data.out.data_all,
        Channel.fromPath("data/01_processed/bulk_rna_seq/*TMB.rds").collect(),
        P13_run_mofa.out.models.collect()
    )
}

workflow {
    W10_mofa()
}
