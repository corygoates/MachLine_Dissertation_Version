import json
import numpy as np
import subprocess as sp
import matplotlib.pyplot as plt
from dev.helper_scripts.case_running_functions import *



def run_cases_for_orientation_and_mesh_density(psi, theta, density):

    # Initialize input
    result_file = "studies/sphere/results/sphere_{0}.vtk".format(density)
    report_file = "studies/sphere/reports/sphere_{0}.json".format(density)

    # Lower-order results
    input_dict ={
        "flow" : {
            "freestream_velocity" : [np.cos(psi)*np.cos(theta), np.sin(psi)*np.cos(theta), np.sin(theta)]
        },
        "geometry" : {
            "file" : "studies/sphere/meshes/sphere_{0}.stl".format(density),
            "spanwise_axis" : "+y"
        },
        "solver" : {
        },
        "post_processing" : {
        },
        "output" : {
            "body_file" : result_file,
            "report_file" : report_file
        }
    }

    # Write to file
    with open(input_filename, 'w') as input_handle:
        json.dump(input_dict, input_handle, indent=4)

    # Run quad
    reports = run_quad(input_filename)

    N_sys = reports[0]["solver_results"]["system_dimension"]
    l_avg = reports[0]["mesh_info"]["average_characteristic_length"]

    C_F = np.zeros((4,3))
    for i, report in enumerate(reports):
        C_F[i,0] = report["total_forces"]["Cx"]
        C_F[i,1] = report["total_forces"]["Cy"]
        C_F[i,2] = report["total_forces"]["Cz"]

    return N_sys, l_avg, C_F


if __name__=="__main__":

    # Options
    input_filename = "studies/sphere/input.json"
    densities = ["ultra_coarse", "very_coarse", "coarse", "medium"]
    psis = np.radians([30.0, 45.0, 60.0])
    thetas = np.radians([30.0, 45.0, 60.0])
    N = []
    l_avg = []
    Cx = np.zeros((len(psis), len(thetas), len(densities), 4))
    Cy = np.zeros((len(psis), len(thetas), len(densities), 4))
    Cz = np.zeros((len(psis), len(thetas), len(densities), 4))

    for i, psi in enumerate(psis):
        for j, theta in enumerate(thetas):
            for k, density in enumerate(densities):

                # Run
                N_sys_i, l_avg_i, C_F = run_cases_for_orientation_and_mesh_density(psi, theta, density)

                # Store
                if i==0 and j==0:
                    N.append(N_sys_i)
                    l_avg.append(l_avg_i)
                Cx[i,j,k,:] = C_F[:,0]
                Cy[i,j,k,:] = C_F[:,1]
                Cz[i,j,k,:] = C_F[:,2]

    # Calculate convergence rates
    orders = [[], [], [], []]
    for i in range(len(psis)):
        for j in range(len(thetas)):
            for k in range(4):
                orders[k].append(get_order_of_convergence(l_avg, Cx[i,j,:,k], truth_from_results=False))
                orders[k].append(get_order_of_convergence(l_avg, Cy[i,j,:,k], truth_from_results=False))
                orders[k].append(get_order_of_convergence(l_avg, Cz[i,j,:,k], truth_from_results=False))

    # Report average orders of convergence
    orders = np.array(orders)
    avg_orders = np.average(orders, axis=1)
    print()
    print("Average Orders of Convergence")
    print("-----------------------------")
    print("Morino, lower-order: ", avg_orders[0], " +/- ", np.std(orders[0]))
    print("Morino, higher-order: ", avg_orders[1], " +/- ", np.std(orders[1]))
    print("Source-free, lower-order: ", avg_orders[2], " +/- ", np.std(orders[2]))
    print("Source-free, higher-order: ", avg_orders[3], " +/- ", np.std(orders[3]))

    # Plot
    line_sytles = ['k-', 'k--', 'k:', 'k-.']
    labels = ['ML', 'MH', 'SL', 'SH']
    plt.figure()
    for i in range(len(psis)):
        for j in range(len(thetas)):
            for k in range(4):
                if i==0 and j==0:
                    plt.plot(l_avg, np.abs(Cx[i,j,:]), line_sytles[k], label=labels[k])
                else:
                    plt.plot(l_avg, np.abs(Cx[i,j,:]), line_sytles[k])
                plt.plot(l_avg, np.abs(Cy[i,j,:]), line_sytles[k])
                plt.plot(l_avg, np.abs(Cz[i,j,:]), line_sytles[k])
    plt.xscale('log')
    plt.yscale('log')
    plt.xlabel('$l_{avg}$')
    plt.ylabel('$C_F$')
    plt.show()