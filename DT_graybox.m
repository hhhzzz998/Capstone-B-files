%% =======================================================================
%  gen_pv_dataset_graybox.m
%  - 批量跑 PVModel.slx（FastRestart）
%  - 基准网格 + 抖动采样，提取 Vmpp, Pmpp, Voc, Isc
%  - 计算归一化标签 ξ = Vmpp/Voc ，π = Pmpp/(Voc*Isc)
%  - 输出 CSV: Ir, T, Vmpp, Pmpp, Voc, Isc, xi, pi
% =======================================================================

mdl      = 'PVModel';            % 模型名（不带 .slx）
constIr  = [mdl '/Ir'];          % 辐照度 Constant 块
constT   = [mdl '/T'];           % 温度 Constant 块
StopTime = 0.05;                 % 一次扫 Voc 用时

% ----- 基准网格 ---------------------------------------------------------
Ir_base = 200:100:1000;          % 9 档
T_base  = 15:5:45;               % 7 档

% ----- 重复与抖动超参 ---------------------------------------------------
R         = 3;                   % 每个网格点重复采样 3 次
sigma_Ir  = 20;                  % ±20 W/m² 抖动
sigma_T   = 1;                   % ±1 °C   抖动

%% ---------- 准备模型 ----------------------------------------------------
load_system(mdl);
set_param(mdl,'FastRestart','on');

%% ---------- 初始化结果表 (8 列) ----------------------------------------
varTypes = {'double','double','double','double','double','double','double','double'};
varNames = {'Ir','T','Vmpp','Pmpp','Voc','Isc','xi','pi'};
data = table('Size',[0 8],'VariableTypes',varTypes,'VariableNames',varNames);

fprintf('🚀 基准 %d×%d，重复 %d 次，共 %d 条采样…\n',...
        numel(Ir_base), numel(T_base), R, numel(Ir_base)*numel(T_base)*R);

for G0 = Ir_base
    for T0 = T_base
        for rep = 1:R
            % --- 生成抖动工况 ------------------------------------------
            G  = G0 + sigma_Ir*randn;
            Tc = T0 + sigma_T *randn;
            set_param(constIr,'Value',num2str(G));
            set_param(constT ,'Value',num2str(Tc));

            % --- 运行仿真 ---------------------------------------------
            simOut = sim(mdl,'StopTime',num2str(StopTime));

            % --- 读取波形 (To Workspace 变量) -------------------------
            V = simOut.V;          % 电压向量  (变量名按需修改)
            I = simOut.I;          % 电流向量  (变量名按需修改)
            P = simOut.P;          % 功率向量

            % ---- 提取开路电压 Voc --------------------------------------------------
            tol = 0.01;                                % 电流阈
            idxVoc = find(I <= tol, 1, 'first');
            if isempty(idxVoc)
                Voc = max(V);                          % 回退
            else
                Voc = V(idxVoc);
            end
            Voc = double(Voc); 
            
            % --- 提取 Vmpp / Pmpp（含二次细化） -----------------------
            [Pm,k] = max(P);  Vm = V(k);
            if k>1 && k<length(P)
                abc = polyfit(V(k-1:k+1), P(k-1:k+1), 2);
                Vm  = -abc(2)/(2*abc(1));
                Pm  = polyval(abc,Vm);
            end

            % --- 计算 Voc、Isc 及归一化 ------------------------------  
            Isc = max(I);
            xi  = Vm / Voc;
            pi  = Pm / (Voc * Isc);

            % --- 追加到表 -------------------------------------------
            data = [data; {G, Tc, Vm, Pm, Voc, Isc, xi, pi}];
        end
    end
end

set_param(mdl,'FastRestart','off');   % 释放资源

%% ---------- 保存 CSV ----------------------------------------------------
writetable(data,'pv_mpp_dataset_graybox.csv');
fprintf('✅  已生成数据集: pv_mpp_dataset_graybox.csv  (共 %d 行)\n',height(data));
