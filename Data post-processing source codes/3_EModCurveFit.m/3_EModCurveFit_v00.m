%%
%VERS�O: Visualiza��o dos resultados parciais do sistema 2

%%---------------------------------------------------------
%C�LCULO DO M�DULO DE ELASTICIDADE
%---------------------------------------------------------
%Assume que a frequ�ncia utilizada � asempre a primeira frequ�ncia do modo
%de flex�o
% clc;
clear all

figure;
numTubo = 4; %Quantidade de tubos

%% DEFINI��ES INICIAIS

%Nome dos resultados:
NomeDoArquivo = ["mod_Tubo 1.txt" "ModElasEMMARM_Tubo 2.txt"...
    "ModElasEMMARM_Tubo 3.txt" "ModElasEMMARM_Tubo 4.txt"];

NomeDoArquivoTemperatura = ["ResultadosFinais_Sistema2_Temperatura_REP4.txt"];

%M�dulo de elasticidade pelo ensaio de frequ�ncia ressonante compress�o cl�ssica. j� convertido ao est�tico
tempoFreqRes = [1.0417    5.0417    6.2917   19.2917   27.0833   33.2500   41.0000];
modElasFreqRes = [8.6575 13.5668 13.7382 14.4251 14.6180 14.5103 14.6737]; %Em GPa
tempoFreqRes_Err = [1.0417    5.0417    6.2917   19.2917   27.0833   33.2500   41.0000];
modElasFreqRes_MeanErr = [8.6575 13.5668 13.7382 14.4251 14.6180 14.5103 14.6737]; %Em GPa
modElasFreqRes_Err= [0.4231 0.4419 0.400 0.4898 0.354 0.3789 0.4261];
tempoClassicComp_Err = [1 2 5 40];
modElasClassicComp_MeanErr = [8.998 11.182 12.245 13.768]; %Em GPa
modElasClassicComp_Err= [0.426 0.715 0.402 1.318];

plotInLog = "N�o"; %Options: Sim | N�o
plotarTemperatura = "N�o"; %Options: Sim | N�o
whatToPlot = "just mean curve"; %Options: all | just curves | just experimental | just mean curve

movingAverage = "no"; %Options: yes | no
movMeanPoints = 5; %N�mero de pontos utilizados na m�dia m�vel

%Declara��o de vari�veis
fittedParameters=zeros(numTubo,6); %Vari�vel que ir� guardar o valor dos par�metros da equa��o ajustada
x=zeros(6,1); %Vari�vel que ir� guardar os par�mtros a serem ajustados
fittedR_Squared = zeros(numTubo); %Vari�vel que ir� guardar o par�metro R de ajuste da equa��o
% fittedResiduals = zeros(200000,numTubo);
markersColors = {[0 0.4470 0.7410];[0.8500 0.3250 0.0980];[0.9290 0.6940 0.1250];[0.4940 0.1840 0.5560]};

fittedModElas_Individual= zeros(numTubo,length([0:0.01:45]));
    
%% PLOTAGEM DOS RESULTADOS DOS TUBOS
for i=1:numTubo
    fileID = fopen(NomeDoArquivo(i),'r');
    
    formatSpec = '%f %f';
    sizeResultados = [2 Inf];
    resultados = fscanf(fileID,formatSpec,sizeResultados);
    resultados = resultados.';
    
    %Obtem as frequ�ncias e os instantes de medi��o a partir dos
    %resultados. O tempo � em dias (para ficar mais f�cil a compara��o com
    %os par�metros de ajuste encontrados por Granja)
    instanteDeAmostragem = resultados(:,1);
    %Os dados a serem ajustados usam o m�dulo em GPa (para ficar mais f�cil
    %a compara��o com os par�metros de ajuste encontrados por Granja)
    modElasEMMARM = resultados(:,2)/1000000000; 
    
    if movingAverage == "yes"
        movMeanPoints = 5;
        modElasEMMARM = movmean(modElasEMMARM,movMeanPoints);
    end
    
    %-----------------
    %Definir a fun��o a ser ajustada � evolu��o do m�dulo de elasticidade
    %-----------------
    %Fun��o proposta por Carette (2015) e utilizada por Granja (2016)
    t = instanteDeAmostragem;
    
    %funModElasFitted =
    %@(x,t)x(1)*exp(-(x(2)./t).^x(3))+x(4).*exp(-(x(5)./t).^x(6))+x(7); %Fun��o
    %de ajuste com 7 par�metros
    
    funModElasFitted = @(x,t)x(1)*exp(-(x(2)./t).^x(3))+x(4).*exp(-(x(5)./t).^x(6));
    %A fun��o "funModElasFitted" depende de 6 ou 7 par�metros: x1 a x7. A
    %correspond�ncia desses par�metros ao da equa��od e Carette �:
    %x(1)->a1; x(2)->tau1; x(3)->beta1; x(4)->a2; x(5)->tau2; x(6)->beta2; x(7)->a3
    
    %-----------------
    %Ajuste da fun��o anal�tica aos dados experimentais, por meio do m�todo
    %de levenberg-marquardt (m�nimos quadrados)
    %-----------------
    %Vetor de ponto de in�cio da fun��o a ser ajustada: valores de x(i), i = 1 a 2
    x0=[mean(modElasEMMARM(round(0.95*end),end)),1,1,mean(modElasEMMARM(round(0.95*end),end)),1,1];
    x0=[1,1,10,1,1,10]; %Outra sugest�o de ponto partida
    
    %Defini��o do m�todo de ajuste e outras op��es
    options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt','Display','off');
    lb = []; %Lower-bound para par�metros de ajuste
    ub = []; %Upper-bound para par�metros de ajuste
    %Obten��o dos par�metros de ajuste da fun��o.
    [x,resnorm,residual] = lsqcurvefit(funModElasFitted,x0,t,modElasEMMARM,lb,ub,options);
    t_plot= [0:0.01:45]; 
    fittedModElas =  funModElasFitted(x(:),t_plot); %C�lculo dos valores a partir da curva ajustada
    fittedModElas_Individual(i,:)=fittedModElas;
    %Outra regress�o:
    %[param,R] = nlinfit(t,modElasEMMARM,funModElasFitted,x0);
    %fittedModElas2 =  funModElasFitted(param,t);
    
    %Salva os par�metros estat�sticos para relat�rio posterior:
    fittedR_Squared(i)=1-resnorm/sum((modElasEMMARM-mean(modElasEMMARM)).^2); %Salva os valores de R^2
    fittedParameters(i,:)=x(:); %Par�metro para salvar todos os par�metros de ajuste
    
    %Plota os dados experimentais e a curva de regress�o
%     if i== 4 || i==4
    if whatToPlot == "all";
%         yyaxis left
        scatter(instanteDeAmostragem, modElasEMMARM,'.','MarkerEdgeColor',cell2mat(markersColors(i)),'MarkerFaceColor',cell2mat(markersColors(i)));
        hold on
        plot(t_plot,fittedModElas,'color',cell2mat(markersColors(i)));
    elseif whatToPlot == "just curves"
%         yyaxis left
        plot(t_plot,fittedModElas,'color',cell2mat(markersColors(i)));
        hold on
    elseif whatToPlot == "just experimental"
%         yyaxis left
        scatter(instanteDeAmostragem, modElasEMMARM,'.','MarkerEdgeColor',cell2mat(markersColors(i)),'MarkerFaceColor',cell2mat(markersColors(i)));
        hold on
    elseif whatToPlot == "just mean curve"
        %do nothing now, it will be done later
    end
%      end
    %   hold on
    %   plot(t,fittedModElas2);
    
end

%% Computa o erro m�dio entre curvas e o desvio padr�o
average=0;
t_StatsComparison=501; %�ndice que define at� qual instante de tempo a an�lise estat�stica ir� considerar
for i=1:numTubo
    average=average+fittedModElas_Individual(i,:);
end
average=average/numTubo;

averageAbsoluteError=zeros(numTubo,length(average(1:t_StatsComparison)));
averageSD=zeros(1,length(average));
for i=1:numTubo
    averageAbsoluteError(i,:)=abs((average(1:t_StatsComparison)-fittedModElas_Individual(i,1:t_StatsComparison))./average(1:t_StatsComparison));
    averageSD=averageSD+((((average-fittedModElas_Individual(i,:))).^2));
end
averageSD=((averageSD./(numTubo-1)).^0.5);

for i=1:numTubo
    disp("------------------------");
    disp("Resultados da replicata "+i+":");
    disp("Erro m�dio: "+mean(averageAbsoluteError(i,2:end)));
    disp("------------------------");
end


%% Plot average curve, if required
if whatToPlot == "just mean curve"
   h(1)=plot(t_plot, average,'r');
   hold on
   % Plota os intervalos acima e abaixo da curva media
%    averageSDPlot=zeros(1,length(averageSD));
%    for i=1:length(averageSD(1,:))
%         averageSDPlot(i)=mean(averageSD(:,i));
%    end
   averageSDPlot=averageSD;

   h(2)=plot(t_plot,average+averageSDPlot,'--r');
   hold on
   h(3)=plot(t_plot,average-averageSDPlot,'--r');
   hold on
end

%% Plota os dados de compress�o cl�ssica
% yyaxis left
% plot(tempoPrensa, modElasPrensa,'*k');
h(4)=errorbar(tempoFreqRes_Err, modElasFreqRes_MeanErr, modElasFreqRes_Err,'*k', 'LineStyle','none');
hold on
h(5)=errorbar(tempoClassicComp_Err, modElasClassicComp_MeanErr, modElasClassicComp_Err,'ob', 'LineStyle','none');
hold on

    
%% Configura��es da plotagem
if plotarTemperatura == "Sim"
    if whatToPlot == "all"
        legend ("EMM-ARM - Tube 1","Fit - Tube 1","EMM-ARM - Tube 2","Fit - Tube 2",...
        "EMM-ARM - Tube 3","Fit - Tube 3","EMM-ARM - Tube 4","Fit - Tube 4","Average curve","Classic Compression");
    elseif whatToPlot =="just curves"
        legend("Fit - Tube 1","Fit - Tube 2",...
        "Fit - Tube 3","Fit - Tube 4","Average curve","Classic Compression");
    elseif whatToPlot =="just experimental"
        legend ("EMM-ARM - Tube 1","EMM-ARM - Tube 2",...
        "EMM-ARM - Tube 3","EMM-ARM - Tube 4","Average curve","Classic Compression");
    end
else
    if whatToPlot == "all"
        legend ("EMM-ARM - Tube 1","Fit - Tube 1","EMM-ARM - Tube 2","Fit - Tube 2",...
        "EMM-ARM - Tube 3","Fit - Tube 3","EMM-ARM - Tube 4","Fit - Tube 4","Average curve","Classic Compression","Temperatura");
    elseif whatToPlot =="just curves"
        legend("Fit - Tube 1","Fit - Tube 2",...
        "Fit - Tube 3","Fit - Tube 4","Average curve","Classic Compression","Temperatura");
    elseif whatToPlot =="just experimental"
        legend ("EMM-ARM - Tube 1","EMM-ARM - Tube 2",...
        "EMM-ARM - Tube 3","EMM-ARM - Tube 4","Average curve","Classic Compression","Temperatura");
    elseif whatToPlot =="just mean curve"
        legend (h([1,2,4,5]),{'EMM-ARM average curve', 'EMM-ARM average � standard deviation curve','Resonant Frequency','Classic Compression'},'location','southeast');
    end
    
end

%% CONFIGURA��O GR�FICA DO PLOT

% legend ("EMM-ARM - LC3 - Tube 1", "EMM-ARM - LC3 - Tube 2",...
%     "Impulse - REF - Eq. 1","Impulse - LC3 - Eq. 1","Impulse - REF - Eq. 2","Impulse - LC3 - Eq. 2");
% legend ("EMM-ARM - System 1","EMM-ARM - System 2","EMM-ARM - System 3","EMM-ARM - System 4","Classic Compression");

if plotInLog == "Sim"
    set(gca,'xscale','log')
else
end

xlabel ("Age (days)");
% yyaxis left
ylabel ("Elastic modulus (GPa)");
% yyaxis right
% ylabel ("Temperature (C)");
% title ("EMM-ARM results - First batch. Corre��o utilizada: "+num2str(corr));
title ("Elastic modulus evolution for Batch 1 (w/b = 0.5)");
yticks([0 2.5 5 7.5 10 12.5 15])
xlim([0 5.2])
ylim([0 15])
grid on

set(gcf,'units','centimeters','position',[5,5,20,15])
