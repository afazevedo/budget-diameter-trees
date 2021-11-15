include("../src/params.jl")
include("../src/read.jl")
include("../heuristics/params.jl")
include("../src/utils.jl")
include("../heuristics/rgh.jl")

using Gurobi, JuMP, MathOptInterface, LightGraphs, LightGraphsFlows, GraphPlot

g_params.file_name = pwd()*"\\instances\\$type_of_tree\\c_v10_a45_d4.txt"
# g_params.file_name = pwd()*"\\instances\\toy.txt"
ins = read_from_files(g_params.file_name)

function my_callback_function(cb_data)    
    V = 1:ins.n
    H = ins.L+1

    num_nodes = (ins.n)*ins.L+1
    graph = LightGraphs.DiGraph(num_nodes)
    source = num_nodes
    capacity_matrix = zeros(num_nodes, num_nodes)

    # Adicionando aresta do vértice artificial para os vértices da primeira camada (A_0)
    for j in V
        add_edge!(graph, source, j)
        capacity_matrix[source, j] = callback_value(cb_data, x_g[1, ins.n+1, j])
        # println("Aresta Grupo 1: [", source, "->", j, "] : ", capacity_matrix[source, j]) 
    end 

    # Adicionando arestas do grupo A_1
    for h in 2:ins.L
        for i in 1:ins.n
            for j in 1:ins.n
                add_edge!(graph, (h-2)*ins.n + i, (h-1)*ins.n + j)   
                capacity_matrix[(h-2)*ins.n + i, (h-1)*ins.n + j] = callback_value(cb_data, x_g[h, i, j])     
                # println("Aresta Grupo 2: [", (h-2)*ins.n + i, "->", (h-1)*ins.n + j, "] : ", capacity_matrix[(h-2)*ins.n + i, (h-1)*ins.n + j]) 
            end 
        end
    end

    # Adicionando arestas do grupo A_2
    for h in 2:ins.L
        for i in 1:ins.n
            node_i = (h-2)*ins.n + i
            node_j = (H-2)*ins.n + i
            add_edge!(graph, node_i, node_j)
            capacity_matrix[node_i, node_j] = callback_value(cb_data, x_g[h, i, i]) 
            # println("Aresta Grupo 3: [", node_i, "->", node_j, "] : ", capacity_matrix[node_i, node_j]) 
        end 
    end 
    
    for t in 1:ins.n   
        subtour, complementary, flow_value = LightGraphsFlows.mincut(graph, source, (H-2)*ins.n + t, capacity_matrix, EdmondsKarpAlgorithm())
        result = zeros(H, ins.n+1, ins.n)

        if flow_value < 1 - g_params.eps
            for u in subtour
                for v in complementary
                    if LightGraphs.has_edge(graph, u, v)
                        if u == source 
                            h = 1
                            ind_u = ins.n+1 
                        else  
                            if u % ins.n == 0
                                ind_u = ins.n 
                            else 
                                ind_u = u % ins.n
                            end 
                            h = ceil(u/ins.n) + 1
                        end 
                        
                        if v % ins.n == 0
                            ind_v = ins.n 
                        else
                            ind_v = v % ins.n
                        end 
                            
                    
                        h = Int(h)           
                        result[h, ind_u, ind_v] = 1
                        capacity_matrix[u, v] = 1
                    end 
                end 
            end 
    
            con = @build_constraint(sum(x_g[h,i,j] for h in 1:H, i in V0, j in V if result[h,i,j] == 1) >= 1)
            # println("Adding $(con) para t=$(t)")
            MOI.submit(model, MOI.LazyConstraint(cb_data), con)
        end   
    end 
end

# Inicialização de um modelo 
model = Model(Gurobi.Optimizer)

# Atributos do modelo
MOI.set(model, MOI.RawParameter("LazyConstraints"), 1)
# set_optimizer_attribute(model, "Cuts", 0)
# set_optimizer_attribute(model, "Presolve", 0)
# set_optimizer_attribute(model, "Heuristics", 0)
# set_optimizer_attribute(model, "Threads", 1)
# set_optimizer_attribute(model, "OutputFlag", 0)

# ins.L = ins.L + 1 # Para que o número de camadas seja par

ins.L = 3

#Conjuntos
V = 1:ins.n
V0 = 1:ins.n+1
H = 1:ins.L+1
ins.B = 252

# Definição das variáveis de decisão
@variable(model, x[i in 1:ins.n+1, j in 1:ins.n; i != j], Bin)
@variable(model, z, Bin)
# @variable(model, 0 <= u[i in V0] <= ins.L+1, Int)
@variable(model, 0 <= w[i in V, j in V] <= 1, Int)
@variable(model, s >= 1, Int)
@variable(model, x_g[h in 1:ins.L+1, i in V0, j in V;
    	(h == 1 && i == ins.n+1) || (h > 1 && i != ins.n+1)], Bin
    )

# Definição da função objetivo
@objective(model, Min, 2*(s-1) + z)

# @objective(model, Min, sum(x[i,j]*ins.c[i,j] for i in V, j in V if i != j))

@constraint(model, central,
    sum(w[i,j] for i in V, j in V if i != j) == z
)

@constraint(model, art[i in V, j in V; i != j],
        w[i,j] <= x[ins.n+1, i]
    )

@constraint(model, art2[i in V, j in V; i != j],
        w[i,j] <= x[ins.n+1, j]
)

@constraint(model, root_out,
    sum(x_g[1, ins.n+1, j] for j in V) == z + 1
)


@constraint(model, teste2[i in V, j in V; i != j], w[i,j] + w[j,i] + x[i,j] + x[j,i] <= 1)

@constraint(model, root[j in V], x[ins.n+1, j] == x_g[1,ins.n+1, j])

@constraint(model, bind_arc[i in V, j in V; i != j], x[i,j] == sum(x_g[h,i,j] for h in 2:ins.L))

@constraint(model, budget,
    sum(ins.c[i,j]*x_g[h,i,j] for h in 1:ins.L+1, i in V, j in V if i != j && h > 1 && i != ins.n+1) + sum(ins.c[i,j]*w[i,j] for i in V, j in V if i != j) <= ins.B
)


# @constraints(model, begin
#     mtz[j in V], u[ins.n+1] - u[j] + (ins.L+1)*x[ins.n+1, j] <= ins.L
#     mtz1[i in V, j in V; i != j], u[i] - u[j] + (ins.L+1)*x[i,j] + (ins.L-1)*x[j,i] <= ins.L
#     # mtz2[i in V], u[i] - u[ins.n+1] + (ins.L-1)*x[ins.n+1,i] <= ins.L
# end)

# @constraint(model, mag[i in V], s >= u[i])

@constraint(model, mag[h in 2:ins.L+1, i in V, j in V; i != j], 
        s >= h*x_g[h,i,j]
    )


for i in 1:ins.n
    for j in 1:ins.n
        if ins.c[i,j] < g_params.eps && i != j
            set_upper_bound(w[i,j], 0.0)
            set_lower_bound(w[i,j], 0.0)
            for h in 1:ins.L+1
                if (h == 1 && i == ins.n+1) || (h > 1 && i != ins.n+1)
                    set_upper_bound(x_g[h,i,j], 0.0)
                    set_lower_bound(x_g[h,i,j], 0.0)
                end
            end
        end
    end
end
# set_upper_bound(u[ins.n+1], 0.0)
# set_lower_bound(u[ins.n+1], 0.0)



MOI.set(model, MOI.LazyConstraintCallback(), my_callback_function)
optimize!(model)


for i in 1:ins.n+1
    for j in 1:ins.n
        if i != j && value(x[i,j]) == 1
            println("A aresta [", i, ",", j, "]", " foi escolhida")
        end 
    end 
end 


value(z)
value(s)


sum(ins.c[i,j]*value(x[i,j]) for i in V for j in V if i != j) + sum(ins.c[i,j]*value(w[i,j]) for i in V, j in V if i != j)
objective_value(model)


for h in 1:ins.L+1
    for i in 1:ins.n+1
        for j in 1:ins.n
            if ((h == 1 && i == ins.n+1) || (h > 1 && i != ins.n+1)) && value(x_g[h,i,j]) == 1
                println("A aresta [",h, ",", i, ",", j, "]", " foi escolhida")
            end 
        end 
    end 
end 

for h in 1:ins.L
    soma = 0
    for i in 1:ins.n+1
        for j in 1:ins.n
            if ((h == 1 && i == ins.n+1) || (h > 1 && i != ins.n+1)) && value(x_g[h,i,j]) == 1
                soma += value(x_g[h,i,j])
            end 
        end 
    end 
    println(soma)
end 