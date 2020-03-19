import "single_sample_rnaseq.wdl" as single_sample_rnaseq
import "feature_counts.wdl" as feature_counts
import "multiqc.wdl" as multiqc
import "fastqc.wdl" as fastqc
import "report.wdl" as reporting


workflow PairedRnaSeqAndQuantWorkflow{
    # This workflow is a 'super' workflow that parallelizes
    # RNA-seq analysis over multiple samples

    Array[File] r1_files
    Array[File] r2_files
    String genome
    File star_index_path
    File gtf
    String output_zip_name
    String git_repo_url
    String git_commit_hash

    Array[Pair[File, File]] fastq_pairs = zip(r1_files, r2_files)


    scatter(item in fastq_pairs){

        call fastqc.run_fastqc as fastqc_for_read1 {
            input:
                fastq = item.left
        }

        call fastqc.run_fastqc as fastqc_for_read2 {
            input:
                fastq = item.right
        }

        call single_sample_rnaseq.SingleSampleRnaSeqWorkflow as single_sample_process{
            input:
                r1_fastq = item.left,
                r2_fastq = item.right,
                star_index_path = star_index_path,
                gtf = gtf
            }
    }

    call feature_counts.concatenate as merge_primary_counts {
        input:
            count_files = single_sample_process.primary_filter_feature_counts_file,
            output_filename = "raw_primary_counts.tsv"
    }

    call feature_counts.concatenate as merge_dedup_counts {
        input:
            count_files = single_sample_process.dedup_feature_counts_file,
            output_filename = "raw_primary_and_deduplicated_counts.tsv"
    }

    call multiqc.create_qc as experimental_qc {
        input:
            star_logs = single_sample_process.star_log,
            fc_logs = single_sample_process.primary_filter_feature_counts_summary,
            r1_fastqc_zips = fastqc_for_read1.fastqc_zip,
            dedup_metrics = single_sample_process.dedup_metrics,
            r2_fastqc_zips = fastqc_for_read2.fastqc_zip
    }

    call reporting.generate_report as generate_report{
        input:
            r1_files = r1_files,
            r2_files = r2_files,
            genome = genome,
            git_commit_hash = git_commit_hash,
            git_repo_url = git_repo_url
    }

    call zip_results {
        input:
            zip_name = output_zip_name,
            primary_fc_file = merge_primary_counts.count_matrix,
            dedup_fc_file = merge_dedup_counts.count_matrix,
            primary_bam_files = single_sample_process.primary_bam,
            primary_bam_index_files = single_sample_process.primary_bam_index,
            star_logs = single_sample_process.star_log,
            dedup_fc_summaries = single_sample_process.dedup_feature_counts_summary, 
            primary_fc_summaries = single_sample_process.primary_filter_feature_counts_summary,
            dedup_metrics = single_sample_process.dedup_metrics,
            multiqc_report = experimental_qc.report,
            analysis_report = generate_report.report
    }

    output {
        File zip_out = zip_results.zip_out
        File alignments_zip = zip_results.alignments_zip
    }

    meta {
        workflow_title : "Paired-end RNA-Seq basic alignment and quantification"
        workflow_short_description : "For alignment-based quantification on a basic paired-end RNA-seq experiment"
        workflow_long_description : "Use this workflow for aligning with STAR and quantifying a paired-end RNA-seq experiment."
    }
}



task zip_results {

    String zip_name 

    File primary_fc_file
    File dedup_fc_file
    Array[File] primary_bam_files
    Array[File] primary_bam_index_files
    Array[File] star_logs
    Array[File] dedup_fc_summaries 
    Array[File] primary_fc_summaries
    Array[File] dedup_metrics
    File multiqc_report
    File analysis_report

    Int disk_size = 1000

    command {

        mkdir alignments
        mv -t alignments ${sep=" " primary_bam_files}
        mv -t alignments ${sep=" " primary_bam_index_files}
        zip -r "alignments.zip" alignments

        mkdir report
        mkdir report/quantifications
        mkdir report/qc
        mkdir report/logs

        mv ${primary_fc_file} report/quantifications/
        mv ${dedup_fc_file} report/quantifications/
        mv ${multiqc_report} report/qc/
        mv -t report/logs ${sep=" " star_logs}
        mv -t report/logs ${sep=" " dedup_fc_summaries}
        mv -t report/logs ${sep=" " primary_fc_summaries}
        mv -t report/logs ${sep=" " dedup_metrics}

        mv ${analysis_report} report/
        zip -r "${zip_name}.zip" report
    }

    output {
        File zip_out = "${zip_name}.zip"
        File alignments_zip = "alignments.zip"
    }

    runtime {
        docker: "docker.io/blawney/star_quant_only:v0.1"
        cpu: 2
        memory: "6 G"
        disks: "local-disk " + disk_size + " HDD"
        preemptible: 0
    }
}
