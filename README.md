# Intelligent Power Grid Use Case

This repository contains detailed instructions to install the testbed architecture and run the scenarios of the Intelligent Power Grid use case. A more comprehensive description of the scenarios and how they showcase FLUIDOS’ advantages for this use case is available in deliverable D7.3.

More specifically this repository contains:

* Instructions to setup a 3-nodes FLUIDOS computing continuum.

* The containerized version of the PDC, adapted to run as FLUIDOSDeployments.

* A distributed database infrastructure based on Percona XtraDB Cluster to provide synchronous replication and fault tolerance. This solution ensures data consistency and persistence across nodes, directly supporting the requirements of persistent storage in the Intelligent Power Grid use case.

* Dedicated Grafana and Prometheus dashboards to provide real-time visualization of the operational status, performance metrics, and evolution of the demonstration scenarios.

* Specific scripts to emulate failure conditions, such as node downtime, hardware malfunction, and latency increase, in order to assess the robustness and resilience of the proposed solutions.

All the developments described above were condensed into automated testbed deployment scripts, which include the installation and configuration of K3s and FLUIDOS nodes, and all the software components required for the demonstrators (workloads, distributed database, monitoring, and fault injection). These scripts enable a reproducible and efficient setup of the Year 2 and Year 3 testbeds, reducing manual configuration efforts and ensuring consistency across deployments, thus providing the operational foundation for experimentation within FLUIDOS.

## License and Acknowledgments
This project is licensed under the Apache License - version 2.0, see the [LICENSE](LICENSE) file for details.

This project includes some previous work done by [Claudio Usai](https://github.com/claudious96), [Claudio Lorina](https://github.com/claudiolor) and [Riccardo Medina](https://github.com/rmedina97) as part of their master thesis at Politecnico di Torino.