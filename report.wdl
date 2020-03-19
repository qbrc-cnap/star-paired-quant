task generate_report {

    Array[String] r1_files
    Array[String] r2_files
    String genome    
    String git_repo_url
    String git_commit_hash
    Int disk_size = 10

    command <<<

        # make a json file with various parameters:
        echo "{" >> config.json
        echo '"genome": "${genome}",' >>config.json
        echo '"git_repo": "${git_repo_url}",' >>config.json
        echo '"git_commit": "${git_commit_hash}",' >>config.json

        generate_report.py \
          -r1 ${sep=" " r1_files} \
          -r2 ${sep=" " r2_files} \
          -j config.json \
          -t /opt/report/report.md \
          -o completed_report.md

        pandoc -H /opt/report/report.css -s completed_report.md -o analysis_report.html
    >>>

    output {
        File report = "analysis_report.html"
    }

    runtime {
        docker: "docker.io/blawney/star_quant_only:v0.1"
        cpu: 2
        memory: "6 G"
        disks: "local-disk " + disk_size + " HDD"
        preemptible: 0
    }
}
