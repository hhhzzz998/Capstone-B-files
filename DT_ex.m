%% =======================================================================
%  gen_pv_dataset_jitter.m
%  - 批量跑 PVModel.slx（FastRestart）
%  - 每个 (Ir,T) 基准网格重复 R 次并加高斯抖动
%  - 依赖 To Workspace:  outV, outP   (Array 格式)
%  - 输出 CSV: Ir, T, Vmpp, Pmpp
% ========================================================================

mdl      = 'PVModel';            % 模型名（不带 .slx）
constIr  = [mdl '/Ir'];          % 辐照度 Constant 块
constT   = [mdl '/T'];           % 温度 Constant 块
StopTime = 0.05;                 % 一次扫 Voc 用时

% ----- 基准网格 ---------------------------------------------------------
Ir_base = 200:100:1000;          % 9 档
T_base  = 15:5:45;               % 7 档

% ----- 重复与抖动超参 ---------------------------------------------------
R         = 3;                   % 每个网格再随机采样 3 次
sigma_Ir  = 20;                  % ±20 W/m² 高斯抖动
sigma_T   = 1;                   % ±1  °C   高斯抖动

%% ---------- 准备模型 ----------------------------------------------------
load_system(mdl);
set_param(mdl,'FastRestart','on');

%% ---------- 初始化空表 --------------------------------------------------
data = table('Size',[0 4], ...
             'VariableTypes',{'double','double','double','double'}, ...
             'VariableNames',{'Ir','T','Vmpp','Pmpp'});

fprintf('🚀 基准 %d×%d，重复 %d 次，共 %d 条采样…\n',...
        numel(Ir_base), numel(T_base), R, ...
        numel(Ir_base)*numel(T_base)*R);

for G0 = Ir_base
    for T0 = T_base
        for rep = 1:R
            % ---- 生成抖动后的工况 -------------------------------------
            G  = G0 + sigma_Ir * randn;
            Tc = T0 + sigma_T  * randn;
            set_param(constIr,'Value',num2str(G));
            set_param(constT ,'Value',num2str(Tc));

            % ---- 运行仿真 -------------------------------------------
            simOut = sim(mdl,'StopTime',num2str(StopTime));

            % ---- 读取波形 -------------------------------------------
            V = simOut.V;           % Voltage 向量
            P = simOut.P;           % Power   向量

            % ---- 提取 MPP（带二次细化） ------------------------------
            [Pm,k] = max(P);  Vm = V(k);
            if k>1 && k<length(P)
                v3 = V(k-1:k+1); p3 = P(k-1:k+1);
                abc = polyfit(v3,p3,2);
                Vm  = -abc(2)/(2*abc(1));
                Pm  = polyval(abc,Vm);
            end

            % ---- 追加到表 -------------------------------------------
            data = [data; {G, Tc, Vm, Pm}];
        end
    end
end

set_param(mdl,'FastRestart','off');   % 释放模型

%% ---------- 保存 CSV ----------------------------------------------------
writetable(data,'pv_mpp_dataset_ext.csv');
fprintf('✅  已生成扩充数据集: pv_mpp_dataset_ext.csv  (共 %d 行)\n',height(data));
