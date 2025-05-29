clc
clear

%% =======================================================================
%  gen_pv_dataset_with_toworkspace.m
%  - 不改模型任何参数，直接批量跑 PVModel.slx
%  - 依赖三个 To Workspace 变量：outV、outI、outP
%  - 输出 CSV: Ir, T, Vmpp, Pmpp  共 63 行
% ========================================================================
mdl = 'PVModel';       % 模型文件名 (不带 .slx)
constIr = [mdl '/Ir']; % 辐照度 Constant 块路径
constT  = [mdl '/T'];  % 温度 Constant 块路径
StopTime = 0.05;       % 一次扫 Voc 用时 (与模型GUI一致即可)

Ir_vals = 200:100:1000;  % 9 档
T_vals  = 15:5:45;       % 7 档
N       = numel(Ir_vals)*numel(T_vals);

%% ---------- 准备模型 ----------------------------------------------------
load_system(mdl);                 % 只加载，不弹窗
set_param(mdl,'FastRestart','on');% 以后每次 sim 秒级返回

%% ---------- 初始化结果表 -----------------------------------------------
data = table('Size',[N 4], ...
    'VariableTypes',{'double','double','double','double'}, ...
    'VariableNames',{'Ir','T','Vmpp','Pmpp'});

row = 1;
fprintf('🚀 批量扫描 %d×%d = %d 个工况…\n',numel(Ir_vals),numel(T_vals),N);

for G = Ir_vals
    set_param(constIr,'Value',num2str(G));
    
    for Tc = T_vals
        set_param(constT,'Value',num2str(Tc));
        
        % ---- 运行仿真：FastRestart 打开时只能传 StopTime ----------
        simOut = sim(mdl,'StopTime',num2str(StopTime));
        
        % ---- 读取 To Workspace 变量 ----------------------------------
        V = simOut.V;          % Voltage 向量
        P = simOut.P;          % Power   向量  (已在模型里 V×I 生成)
        
        % ---- 提取 MPP (含 3 点抛物线细化) ----------------------------
        [Pm, k] = max(P); Vm = V(k);
        if k>1 && k<length(P)     % 有左右邻点时二次拟合
            v3 = V(k-1:k+1); p3 = P(k-1:k+1);
            abc = polyfit(v3,p3,2);
            Vm  = -abc(2)/(2*abc(1));
            Pm  = polyval(abc,Vm);
        end
        
        % ---- 写入表格 ------------------------------------------------
        data{row,:} = [G Tc Vm Pm];
        row = row + 1;
    end
end

set_param(mdl,'FastRestart','off');  % 清理

%% ---------- 保存 CSV ----------------------------------------------------
writetable(data,'pv_mpp_dataset.csv');
fprintf('✅ CSV 已保存: pv_mpp_dataset.csv   (共 %d 行)\n',height(data));


